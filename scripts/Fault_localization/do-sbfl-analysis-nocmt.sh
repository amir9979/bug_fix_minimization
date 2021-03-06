#!/bin/bash

HERE=$(greadlink --canonicalize "$(dirname "${BASH_SOURCE[0]}")")
PATH="$HERE:$PATH"

USAGE="$0 [--restrictions-file FILE] PROJECT BUG COVERAGE_MATRIX STATEMENT_NAMES"
die() {
  echo "$@" >&2
  exit 1
}

RESTRICTIONS_FILE=''
while [[ "$1" = --* ]]; do
  OPTION=$1; shift
  case $OPTION in
    (--restrictions-file)
      RESTRICTIONS_FILE=$1; shift;;
    (*)
      die "usage: $USAGE";;
  esac
done

if [ "$#" != 4 ]; then echo "usage: $USAGE" >&2; exit 1; fi
PROJECT=$1
BUG=$2
COVERAGE_MATRIX="$(greadlink --canonicalize "$3")"; if [ ! -f "$COVERAGE_MATRIX" ]; then echo "given coverage matrix does not exist" >&2; exit 1; fi
STATEMENT_NAMES="$(greadlink --canonicalize "$4")"; if [ ! -f "$STATEMENT_NAMES" ]; then echo "given statement-names file does not exist" >&2; exit 1; fi

for FORMULA in tarantula ochiai opt2 barinel dstar2 muse jaccard; do
  if [ "$RESTRICTIONS_FILE" ]; then check-restrictions "$RESTRICTIONS_FILE" --formula "$FORMULA" || continue; fi
  DIR="formula-$FORMULA"; mkdir -p "$DIR"; pushd "$DIR" >/dev/null

  for TOTAL_DEFN in tests elements; do
    if [ "$RESTRICTIONS_FILE" ]; then check-restrictions "$RESTRICTIONS_FILE" --total-defn "$TOTAL_DEFN" || continue; fi
    DIR="totaldefn-$TOTAL_DEFN"; mkdir -p "$DIR"; pushd "$DIR" >/dev/null

    STMT_SUSPS_FILE="$(pwd)/stmt-susps.txt"
    crush-matrix --formula "$FORMULA" --matrix "$COVERAGE_MATRIX" \
                 --element-type 'Statement' \
                 --element-names "$STATEMENT_NAMES" \
                 --total-defn "$TOTAL_DEFN" \
                 --output "$STMT_SUSPS_FILE" || exit 1

    LINE_SUSPS_FILE=$(pwd)/line-susps.txt
    stmt-susps-to-line-susps --stmt-susps "$STMT_SUSPS_FILE" \
                             --source-code-lines "$HERE/source-code-lines/$PROJECT-${BUG}b.source-code.lines" \
                             --output "$LINE_SUSPS_FILE"
    for SCORING_SCHEME in first last mean median; do
      if [ "$RESTRICTIONS_FILE" ]; then check-restrictions "$RESTRICTIONS_FILE" --scoring-scheme "$SCORING_SCHEME" || continue; fi
      DIR="scoring-$SCORING_SCHEME"; mkdir -p "$DIR"; pushd "$DIR" >/dev/null
      DEST="$(pwd)/score.txt"
      score-ranking --project "$PROJECT" --bug "$BUG" \
                    --line-susps <(tail -n +2 "$LINE_SUSPS_FILE") \
                    --scoring-scheme "$SCORING_SCHEME" \
                    --sloc-csv "$HERE/buggy-lines-nocmt/sloc.csv" \
                    --buggy-lines "$HERE/buggy-lines-nocmt/$PROJECT-$BUG.buggy.lines" \
                    --output "$DEST"
      popd >/dev/null
    done

    popd >/dev/null
  done

  popd >/dev/null
done
