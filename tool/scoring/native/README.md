MinaCalc standalone, upstream commit 38687d1fc43994652e9808eae4e9d63b167bc27b
(https://github.com/kangalio/minacalc-standalone), MIT licence in LICENSE.txt.
The C bridge additionally exposes calc_ssr_research for fixed precision goals.

Build on macOS or Linux:

    cmake -S tool/scoring/native -B build/scoring-native
    cmake --build build/scoring-native --parallel 2

Copy the resulting shared library into a versioned scoring bundle. Each
platform must pass corpus conformance before that bundle is published.
