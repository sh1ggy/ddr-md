// Offline model-compare harness.
//
// Runs the REAL DdrocrInstance pipeline (Details detect -> homography -> 4000x5000
// warp -> combined-ROI det+rec -> overlap/anchor field pick) over a folder of test
// screenshots, once per model triplet, and writes a per-field CSV so each
// (image, field) can be compared across models on a single row.
//
// Build: see CMakeLists.txt in this directory.

#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <tuple>
#include <vector>

#include <dirent.h>
#include <sys/stat.h>

#include <opencv2/opencv.hpp>

#include "ddrocr_instance.h"
#include "ocr_wrapper.h"

// The pipeline sources call platform_log via an extern; supply a stderr impl so
// we don't have to pull in the FFI/ObjC translation units that define it in-app.
void platform_log(const char *fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vfprintf(stderr, fmt, args);
    va_end(args);
}

namespace
{
struct NamedModelSet
{
    std::string label;
    ModelSet    models;
};

struct NamedRoiSet
{
    std::string label;
    COCRConfig  cfg;
};

// Mirrors lib/ocr_config.dart. roi[] rows are {x1,y1,x2,y2,expand_x,expand_y}
// in ROI_IDX_* order: details, score, marvelous, perfect, great, good, miss,
// flare, title, username, difficulty, max_combo. Keep in sync with
// ocrRoi (+ its paired ocrCombinedRoi) in Dart.
COCRConfig makeReferenceConfig()
{
    COCRConfig c; // inherits non-ROI defaults (border, thresholds, etc.)
    // Match the app: lib/ocr_config.dart ocrDetailsTemplateMinScore = 0.4
    // (the C++ COCRConfig default is 0.55, but the app sends 0.4 via FFI).
    c.details_template_min_score = 0.4;
    int roi[12][6] = {
        {1669, 864, 1920, 936, 0, 0},   // details
        {2129, 1005, 2273, 1042, 5, 6}, // score
        {1540, 1013, 1642, 1050, 0, 0}, // marvelous
        {1540, 1049, 1642, 1086, 0, 0}, // perfect
        {1540, 1085, 1642, 1122, 0, 0}, // great
        {1540, 1121, 1642, 1158, 0, 0}, // good
        {1540, 1193, 1642, 1230, 0, 2}, // miss
        {1385, 954, 1507, 984, 0, 0},   // flare
        {1051, 669, 1506, 719, 0, 0},   // title
        {1752, 181, 1952, 220, 0, 0},   // username
        {1766, 233, 2026, 300, 0, 0},   // difficulty
        {2098, 1154, 2279, 1202, 0, 0}, // max_combo
    };
    memcpy(c.roi, roi, sizeof(roi));
    int combined[4] = {1299, 860, 2296, 1239};
    memcpy(c.combinedRoi, combined, sizeof(combined));
    return c;
}

// The 12 fields in OCRResults, in a fixed display order.
const std::vector<std::string> kFields = {
    "score", "marvelous", "perfect", "great", "good", "miss",
    "flare", "title", "username", "difficulty", "max_combo"};
// (note: "ok" is not a field in OCRResults; OCRResults has 11 fields total)

// Pull a field's OCRResult out of OCRResults by name.
const OCRResult &fieldResult(const OCRResults &r, const std::string &f)
{
    if (f == "score")      return r.score;
    if (f == "marvelous")  return r.marvelous;
    if (f == "perfect")    return r.perfect;
    if (f == "great")      return r.great;
    if (f == "good")       return r.good;
    if (f == "miss")       return r.miss;
    if (f == "flare")      return r.flare;
    if (f == "title")      return r.title;
    if (f == "username")   return r.username;
    if (f == "difficulty") return r.difficulty;
    if (f == "max_combo")  return r.max_combo;
    static OCRResult empty;
    return empty;
}

std::string csvQuote(const std::string &s)
{
    std::string out = "\"";
    for (char c : s)
    {
        if (c == '"') out += "\"\"";
        else          out += c;
    }
    out += "\"";
    return out;
}

std::vector<std::string> listJpegs(const std::string &dir)
{
    std::vector<std::string> files;
    DIR *d = opendir(dir.c_str());
    if (!d) return files;
    struct dirent *ent;
    while ((ent = readdir(d)) != nullptr)
    {
        std::string name = ent->d_name;
        if (name.size() > 5 &&
            (name.substr(name.size() - 5) == ".jpeg" ||
             name.substr(name.size() - 4) == ".jpg"))
            files.push_back(name);
    }
    closedir(d);
    std::sort(files.begin(), files.end());
    return files;
}

std::string argValue(int argc, char **argv, const std::string &flag,
                     const std::string &fallback)
{
    for (int i = 1; i + 1 < argc; ++i)
        if (flag == argv[i]) return argv[i + 1];
    return fallback;
}

std::string dirName(const std::string &p)
{
    auto pos = p.find_last_of('/');
    return pos == std::string::npos ? "." : p.substr(0, pos);
}

// Repo root derived from the executable path so the tool works from ANY cwd.
// Binary lives at <root>/native_opencv/tools/model_compare/build/model_compare,
// i.e. five directory levels below the repo root.
std::string repoRootFromArgv0(const char *argv0)
{
    char buf[4096];
    std::string exe = (realpath(argv0, buf) ? std::string(buf) : std::string(argv0));
    std::string p = exe;
    for (int i = 0; i < 5; ++i) p = dirName(p); // strip /native_opencv/tools/model_compare/build/<bin>
    return p.empty() ? "." : p;
}

bool dirExists(const std::string &p)
{
    struct stat st;
    return stat(p.c_str(), &st) == 0 && (st.st_mode & S_IFDIR);
}
} // namespace

int main(int argc, char **argv)
{
    // Anchor default paths to the repo root (from argv[0]) so the tool runs
    // from any working directory. Explicit --flags still override.
    const std::string root = repoRootFromArgv0(argv[0]);
    const std::string toolDir = root + "/native_opencv/tools/model_compare";
    const std::string assetsDir = argValue(argc, argv, "--assets", root + "/assets");
    const std::string testsDir  = argValue(argc, argv, "--tests", toolDir + "/tests");
    const std::string outPath   = argValue(argc, argv, "--out", toolDir + "/results.csv");

    const std::vector<NamedModelSet> modelSets = {
        {"mobile_v5", {"ppocr_mobile_rec.onnx", "ppocr_mobile_det.onnx", "ppocrv5_dict.txt"}},
        {"small_v6",  {"ppocr_small_rec.onnx",  "ppocr_small_det.onnx",  "ppocrv6_small_dict.txt"}},
        {"tiny_v6",   {"ppocr_tiny_rec.onnx",   "ppocr_tiny_det.onnx",   "ppocrv6_dict.txt"}},
        {"medium_v6", {"ppocr_medium_rec.onnx", "ppocr_medium_det.onnx", "ppocrv6_medium_dict.txt"}},
    };

    const std::vector<NamedRoiSet> roiSets = {
        {"reference", makeReferenceConfig()},
    };

    fprintf(stderr, "Repo root: %s\n", root.c_str());
    std::vector<std::string> images = listJpegs(testsDir);
    if (images.empty())
    {
        if (!dirExists(testsDir))
            fprintf(stderr, "Tests dir does not exist: %s\n", testsDir.c_str());
        else
            fprintf(stderr, "No .jpeg/.jpg images found in %s\n", testsDir.c_str());
        fprintf(stderr, "Pass --tests <dir> to override.\n");
        return 1;
    }
    fprintf(stderr, "Found %zu test images in %s\n", images.size(), testsDir.c_str());

    // Keyed by (image, roiSet, field) -> per-model text/conf, and
    // (image, roiSet, model) -> warped flag.
    using FieldKey = std::tuple<std::string, std::string, std::string>;
    using WarpKey  = std::tuple<std::string, std::string, std::string>;
    std::map<FieldKey, std::map<std::string, OCRResult>> results;
    std::map<WarpKey, int> warpedFlag;
    // (image, roiSet, model) -> {totalMs, combinedDetectRecMs} for perf compare.
    std::map<WarpKey, std::pair<int64_t, int64_t>> timingMs;

    // Details-badge template match is computed pre-warp on the raw image, so it
    // is independent of roiSet and model — one value per image. Capture it once.
    struct DetailsInfo { float score = -1.0f; float scale = 0.0f; int candidates = 0; };
    std::map<std::string, DetailsInfo> detailsByImage;

    // Annotated combined-ROI crops (det boxes + recognised text + field
    // anchors), kept in memory keyed by (image, roiSet, model), then written to
    // disk for every model/image/warped-roiSet after all runs complete.
    std::map<std::tuple<std::string, std::string, std::string>, cv::Mat> annotated;

    for (const auto &rs : roiSets)
    {
        for (const auto &ms : modelSets)
        {
            fprintf(stderr, "\n=== roi=%s model=%s ===\n",
                    rs.label.c_str(), ms.label.c_str());
            // One instance per (roiSet, model): models load once, reused across
            // all images. Each roiSet carries its own COCRConfig.
            DdrocrInstance inst(assetsDir, rs.cfg, &ms.models);
            // Render the annotated crop into the result, but never write debug
            // files / dirs into assets.
            inst.diskDebug = false;

            for (const auto &imgName : images)
            {
                std::string path = testsDir + "/" + imgName;
                cv::Mat img = cv::imread(path, cv::IMREAD_COLOR);
                if (img.empty())
                {
                    fprintf(stderr, "  failed to read %s\n", path.c_str());
                    continue;
                }

                ProcessImgResult r = inst.process_image(
                    img, DetectionSide::FIRST, DebugImageType::ON);

                // detailsRoiIndex >= 0 is the true "full pipeline ran" signal:
                // isDetected only means candidate blobs were found, not that the
                // Details badge matched and the warp executed.
                int warped = (r.detailsRoiIndex >= 0) ? 1 : 0;
                warpedFlag[{imgName, rs.label, ms.label}] = warped;
                timingMs[{imgName, rs.label, ms.label}] = {r.totalMs, r.combinedDetectRecMs};
                for (const auto &f : kFields)
                    results[{imgName, rs.label, f}][ms.label] =
                        fieldResult(r.ocrResults, f);

                if (!r.detectAnnotated.empty())
                    annotated[{imgName, rs.label, ms.label}] = r.detectAnnotated;

                // Same across roiSet/model — record once (first wins).
                if (detailsByImage.find(imgName) == detailsByImage.end())
                    detailsByImage[imgName] =
                        {r.detailsMatchScore, r.detailsMatchScale, r.detailsCandidateCount};

                fprintf(stderr, "  %s warped=%d score='%s'\n",
                        imgName.c_str(), warped, r.ocrResults.score.text.c_str());
            }
        }
    }

    // ----- Write the wide per-field CSV -----
    // One row per (image, roi_set, field); per-model text/conf/warped columns.
    FILE *out = fopen(outPath.c_str(), "w");
    if (!out)
    {
        fprintf(stderr, "Failed to open output %s\n", outPath.c_str());
        return 1;
    }

    // Header. The three details_* columns are per-image (the Details-badge
    // template match runs pre-warp, independent of roiSet/model), so they
    // repeat identically across every row of an image — read them as a single
    // merged value per image. details_match_score is TM_CCOEFF_NORMED of the
    // best HSV candidate (best score even when below the accept threshold, so
    // you can see near-misses); details_threshold is the accept cutoff;
    // details_matched = 1 if score >= threshold (warp proceeds).
    fprintf(out, "image,details_match_score,details_match_scale,details_candidates,"
                 "details_threshold,details_matched,roi_set,field");
    for (const auto &ms : modelSets)
        fprintf(out, ",%s_text,%s_conf", ms.label.c_str(), ms.label.c_str());
    // one "warped" column per model: 1 = Details matched and the 4000x5000
    // warp ran (fields are real reads); 0 = pipeline bailed before warp.
    for (const auto &ms : modelSets)
        fprintf(out, ",%s_warped", ms.label.c_str());
    // Per-model wall-clock timing (ms), repeated across this image/roiSet's field
    // rows (timing is per image, not per field). _total_ms = whole process_image;
    // _detrec_ms = just the score-panel detect+recognise (model-dependent cost).
    // -1 = stage didn't run (e.g. Details match failed, no warp).
    for (const auto &ms : modelSets)
        fprintf(out, ",%s_total_ms,%s_detrec_ms", ms.label.c_str(), ms.label.c_str());
    fprintf(out, "\n");

    // Accept threshold is a config constant shared by all runs.
    const double detThreshold = roiSets.front().cfg.details_template_min_score;

    for (const auto &imgName : images)
    {
        const DetailsInfo &di = detailsByImage[imgName];
        int detMatched = (di.score >= (float)detThreshold) ? 1 : 0;
        for (const auto &rs : roiSets)
        {
            for (const auto &f : kFields)
            {
                fprintf(out, "%s,%.3f,%.2f,%d,%.2f,%d,%s,%s",
                        imgName.c_str(), di.score, di.scale, di.candidates,
                        detThreshold, detMatched, rs.label.c_str(), f.c_str());
                auto &perModel = results[{imgName, rs.label, f}];
                for (const auto &ms : modelSets)
                {
                    const OCRResult &res = perModel[ms.label];
                    fprintf(out, ",%s,%.3f", csvQuote(res.text).c_str(), res.confidence);
                }
                for (const auto &ms : modelSets)
                    fprintf(out, ",%d", warpedFlag[{imgName, rs.label, ms.label}]);
                for (const auto &ms : modelSets)
                {
                    auto t = timingMs[{imgName, rs.label, ms.label}];
                    fprintf(out, ",%lld,%lld", (long long)t.first, (long long)t.second);
                }
                fprintf(out, "\n");
            }
        }
    }
    fclose(out);

    char abspath[4096];
    if (realpath(outPath.c_str(), abspath))
        fprintf(stderr, "\nWrote CSV: %s\n", abspath);
    else
        fprintf(stderr, "\nWrote CSV: %s\n", outPath.c_str());

    // ----- Save annotated combined-ROI crops (folder per model) -----
    // Save EVERY crop we captured: one per (model, image, warped roiSet). Each
    // shows what det+rec actually saw — detection boxes (green) with recognised
    // text/conf, plus the per-field anchor rectangles (cyan) the picker matches
    // against. Filenames are <image-stem>__<roiSet>.png so the viewer can find
    // them deterministically. A crop only exists when that roiSet warped.
    const std::string resultsRoot = argValue(argc, argv, "--images-out",
                                             toolDir + "/results_images");
    mkdir(resultsRoot.c_str(), 0755);
    for (const auto &ms : modelSets)
        mkdir((resultsRoot + "/" + ms.label).c_str(), 0755);

    int saved = 0;
    for (const auto &kv : annotated)
    {
        const auto &[imgName, roiSet, model] = kv.first;
        if (kv.second.empty()) continue;
        std::string imgStem = imgName.substr(0, imgName.find_last_of('.'));
        // <root>/<model>/<image-stem>__<roiSet>.png
        std::string fn = resultsRoot + "/" + model + "/" +
            imgStem + "__" + roiSet + ".png";
        cv::imwrite(fn, kv.second);
        ++saved;
    }
    char imgAbs[4096];
    const char *rootShown = realpath(resultsRoot.c_str(), imgAbs) ? imgAbs : resultsRoot.c_str();
    fprintf(stderr, "Saved %d annotated crops (all models/images/warped roiSets) under: %s\n",
            saved, rootShown);
    return 0;
}
