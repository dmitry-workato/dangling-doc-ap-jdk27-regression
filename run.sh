#!/bin/sh
# Usage: ./run.sh [JAVA_HOME ...]      (default: the javac on PATH)
set -e
cd "$(dirname "$0")"
rm -rf out && mkdir -p out

for home in "${@:-}"; do
    if [ -n "$home" ]; then javac="$home/bin/javac"; else javac="javac"; fi
    echo "=============================================================="
    "$javac" -version
    echo "=============================================================="

    "$javac" -d out/proc NoopProcessor.java

    echo "--- (a) no annotation processing -----------------------------"
    "$javac" -d out/a -Xlint:dangling-doc-comments Plain.java || true

    echo "--- (b) same, with a do-nothing annotation processor ---------"
    "$javac" -d out/b -Xlint:dangling-doc-comments \
        -processorpath out/proc -processor NoopProcessor Plain.java || true
    echo
done
