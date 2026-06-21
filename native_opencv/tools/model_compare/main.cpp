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
// flare, title, username, difficulty, max_combo. Keep these two in sync with
// ocrRoiReference / ocrRoiImperfect (+ their paired combinedRoi) in Dart.
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

COCRConfig makeImperfectConfig()
{
    COCRConfig c;
    c.details_template_min_score = 0.4; // match app — see makeReferenceConfig
    int roi[12][6] = {
        {2122, 2344, 2448, 2435, 0, 0}, // details
        {2710, 2527, 2933, 2578, 5, 6}, // score
        {1986, 2528, 2089, 2576, 0, 0}, // marvelous
        {1986, 2576, 2089, 2625, 0, 0}, // perfect
        {1986, 2625, 2089, 2680, 0, 0}, // great
        {1986, 2680, 2089, 2726, 0, 0}, // good
        {1986, 2780, 2089, 2827, 0, 2}, // miss
        {1768, 2454, 1768, 2454, 0, 0}, // flare
        {1353, 2106, 1849, 2152, 0, 0}, // title
        {2215, 1486, 2494, 1535, 0, 0}, // username
        {2128, 1559, 2569, 1619, 0, 0}, // difficulty
        {2690, 2729, 2797, 2771, 0, 0}, // max_combo
    };
    memcpy(c.roi, roi, sizeof(roi));
    int combined[4] = {1641, 2339, 2936, 2818};
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
    };

    const std::vector<NamedRoiSet> roiSets = {
        {"reference", makeReferenceConfig()},
        {"imperfect", makeImperfectConfig()},
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

    // Details-badge template match is computed pre-warp on the raw image, so it
    // is independent of roiSet and model — one value per image. Capture it once.
    struct DetailsInfo { float score = -1.0f; float scale = 0.0f; int candidates = 0; };
    std::map<std::string, DetailsInfo> detailsByImage;

    // Annotated combined-ROI crops (det boxes + recognised text + field
    // anchors), kept in memory keyed by (image, roiSet, model). Only the
    // high-value subset is written to disk after all runs complete.
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

    // ----- Save high-value annotated crops (folder per model) -----
    // Kept deliberately minimal: the only cases worth eyeballing det+rec are
    // where the models genuinely diverge on the marquee SCORE field's DIGITS
    // (commas/format stripped, so "998670" vs "998,670" does NOT count), or
    // where the Details match was a near-miss (within 0.1 below threshold).
    // Per-field blank-vs-zero noise on good/great/miss is excluded — it's not a
    // det/rec-quality signal. We save at most ONE roiSet per image (prefer
    // reference) and one crop per model so the folders line up for compare.
    const std::string resultsRoot = argValue(argc, argv, "--images-out",
                                             toolDir + "/results_images");
    mkdir(resultsRoot.c_str(), 0755);
    for (const auto &ms : modelSets)
        mkdir((resultsRoot + "/" + ms.label).c_str(), 0755);

    auto digitsOnly = [](const std::string &s) {
        std::string d;
        for (char c : s) if (c >= '0' && c <= '9') d += c;
        return d;
    };
    auto scoreDigitsDisagree = [&](const std::string &imgName, const std::string &roi) {
        auto &pm = results[{imgName, roi, "score"}];
        std::string a = digitsOnly(pm[modelSets[0].label].text);
        for (size_t i = 1; i < modelSets.size(); ++i)
            if (digitsOnly(pm[modelSets[i].label].text) != a) return true;
        return false;
    };

    int saved = 0, imagesSaved = 0;
    for (const auto &imgName : images)
    {
        const DetailsInfo &di = detailsByImage[imgName];
        bool nearMiss = di.score < (float)detThreshold &&
                        di.score >= (float)detThreshold - 0.1f;
        std::string imgStem = imgName.substr(0, imgName.find_last_of('.'));

        // Choose at most one roiSet for this image (prefer reference).
        const NamedRoiSet *chosen = nullptr;
        bool chosenDisagree = false;
        for (const auto &rs : roiSets)
        {
            bool disagree = scoreDigitsDisagree(imgName, rs.label);
            if (disagree || nearMiss)
            {
                if (!chosen || rs.label == "reference")
                {
                    chosen = &rs;
                    chosenDisagree = disagree;
                }
            }
        }
        if (!chosen) continue;

        const char *reason = chosenDisagree ? (nearMiss ? "scorediff_nearmiss" : "scorediff")
                                            : "nearmiss";
        bool any = false;
        for (const auto &ms : modelSets)
        {
            auto it = annotated.find({imgName, chosen->label, ms.label});
            if (it == annotated.end() || it->second.empty()) continue;
            // <root>/<model>/<image>__<roiSet>__<reason>.png
            std::string fn = resultsRoot + "/" + ms.label + "/" +
                imgStem + "__" + chosen->label + "__" + reason + ".png";
            cv::imwrite(fn, it->second);
            ++saved;
            any = true;
        }
        if (any) ++imagesSaved;
    }
    fprintf(stderr, "High-value images: %d (%d crops across %d model folders)\n",
            imagesSaved, saved, (int)modelSets.size());
    char imgAbs[4096];
    if (realpath(resultsRoot.c_str(), imgAbs))
        fprintf(stderr, "Saved %d high-value annotated crops under: %s\n", saved, imgAbs);
    else
        fprintf(stderr, "Saved %d high-value annotated crops under: %s\n", saved, resultsRoot.c_str());
    return 0;
}
