#!/usr/bin/env bash
# Black + Clang formatter (if installed). This script formats all changed files from the last mergebase.
# You are encouraged to run this locally before pushing changes for review.

# Cause the script to exit if a single command fails
set -euo pipefail

FLAKE8_VERSION_REQUIRED="3.9.1"
BLACK_VERSION_REQUIRED="21.12b0"
SHELLCHECK_VERSION_REQUIRED="0.7.1"
MYPY_VERSION_REQUIRED="0.782"
ISORT_VERSION_REQUIRED="5.10.1"

check_python_command_exist() {
    VERSION=""
    case "$1" in
        black)
            VERSION=$BLACK_VERSION_REQUIRED
            ;;
        flake8)
            VERSION=$FLAKE8_VERSION_REQUIRED
            ;;
        mypy)
            VERSION=$MYPY_VERSION_REQUIRED
            ;;
        isort)
            VERSION=$ISORT_VERSION_REQUIRED
            ;;
        *)
            echo "$1 is not a required dependency"
            exit 1
    esac
    if ! [ -x "$(command -v "$1")" ]; then
        echo "$1 not installed. Install the python package with: pip install $1==$VERSION"
        exit 1
    fi
}

check_docstyle() {
    echo "Checking docstyle..."
    violations=$(git ls-files | grep '.py$' | xargs grep -E '^[ a-z_]+ \([a-zA-Z]+\): ' || true)
    if [[ -n "$violations" ]]; then
        echo
        echo "=== Found Ray docstyle violations ==="
        echo "$violations"
        echo
        echo "Per the Google pydoc style, omit types from pydoc args as they are redundant: https://docs.ray.io/en/latest/ray-contribute/getting-involved.html#code-style "
        exit 1
    fi
    return 0
}

check_python_command_exist black
check_python_command_exist flake8
check_python_command_exist mypy
check_python_command_exist isort

# this stops git rev-parse from failing if we run this from the .git directory
builtin cd "$(dirname "${BASH_SOURCE:-$0}")"

ROOT="$(git rev-parse --show-toplevel)"
builtin cd "$ROOT" || exit 1

# NOTE(edoakes): black version differs based on installation method:
#   Option 1) 'black, 21.12b0 (compiled: no)'
#   Option 2) 'black, version 21.12b0'
BLACK_VERSION_STR=$(black --version)
if [[ "$BLACK_VERSION_STR" == *"compiled"* ]]
then
    BLACK_VERSION=$(echo "$BLACK_VERSION_STR" | awk '{print $2}')
else
    BLACK_VERSION=$(echo "$BLACK_VERSION_STR" | awk '{print $3}')
fi
FLAKE8_VERSION=$(flake8 --version | head -n 1 | awk '{print $1}')
MYPY_VERSION=$(mypy --version | awk '{print $2}')
ISORT_VERSION=$(isort --version | grep VERSION | awk '{print $2}')
GOOGLE_JAVA_FORMAT_JAR=/tmp/google-java-format-1.7-all-deps.jar

# params: tool name, tool version, required version
tool_version_check() {
    if [ "$2" != "$3" ]; then
        echo "WARNING: Ray uses $1 $3, You currently are using $2. This might generate different results."
    fi
}

tool_version_check "flake8" "$FLAKE8_VERSION" "$FLAKE8_VERSION_REQUIRED"
tool_version_check "black" "$BLACK_VERSION" "$BLACK_VERSION_REQUIRED"
tool_version_check "mypy" "$MYPY_VERSION" "$MYPY_VERSION_REQUIRED"
tool_version_check "isort" "$ISORT_VERSION" "$ISORT_VERSION_REQUIRED"

if command -v shellcheck >/dev/null; then
    SHELLCHECK_VERSION=$(shellcheck --version | awk '/^version:/ {print $2}')
    tool_version_check "shellcheck" "$SHELLCHECK_VERSION" "$SHELLCHECK_VERSION_REQUIRED"
else
    echo "INFO: Ray uses shellcheck for shell scripts, which is not installed. You may install shellcheck=$SHELLCHECK_VERSION_REQUIRED with your system package manager."
fi

if command -v clang-format >/dev/null; then
  CLANG_FORMAT_VERSION=$(clang-format --version | awk '{print $3}')
  tool_version_check "clang-format" "$CLANG_FORMAT_VERSION" "12.0.0"
else
    echo "WARNING: clang-format is not installed!"
fi

if command -v java >/dev/null; then
  if [ ! -f "$GOOGLE_JAVA_FORMAT_JAR" ]; then
    echo "Java code format tool google-java-format.jar is not installed, start to install it."
    wget https://github.com/google/google-java-format/releases/download/google-java-format-1.7/google-java-format-1.7-all-deps.jar -O "$GOOGLE_JAVA_FORMAT_JAR"
  fi
else
    echo "WARNING:java is not installed, skip format java files!"
fi

if [[ $(flake8 --version) != *"flake8_quotes"* ]]; then
    echo "WARNING: Ray uses flake8 with flake8_quotes. Might error without it. Install with: pip install flake8-quotes"
fi

if [[ $(flake8 --version) != *"flake8-bugbear"* ]]; then
    echo "WARNING: Ray uses flake8 with flake8-bugbear. Might error without it. Install with: pip install flake8-bugbear"
fi

SHELLCHECK_FLAGS=(
  --exclude=1090  # "Can't follow non-constant source. Use a directive to specify location."
  --exclude=1091  # "Not following {file} due to some error"
  --exclude=2207  # "Prefer mapfile or read -a to split command output (or quote to avoid splitting)." -- these aren't compatible with macOS's old Bash
)

# TODO(dmitri): When more of the codebase is typed properly, the mypy flags
# should be set to do a more stringent check.
MYPY_FLAGS=(
    '--follow-imports=skip'
    '--ignore-missing-imports'
)

MYPY_FILES=(
    # Relative to python/ray
    'autoscaler/node_provider.py'
    'autoscaler/sdk/__init__.py'
    'autoscaler/sdk/sdk.py'
    'autoscaler/_private/commands.py'
    # TODO(dmitri) Fails with meaningless error, maybe due to a bug in the mypy version
    # in the CI. Type check once we get serious about type checking:
    #'ray_operator/operator.py'
    'ray_operator/operator_utils.py'
    '_private/gcs_utils.py'
)

ISORT_PATHS=(
    # TODO: Expand this list and remove once it is applied to the entire codebase.
    'python/ray/autoscaler/_private/'
)

BLACK_EXCLUDES=(
    '--force-exclude' 'python/ray/cloudpickle/*'
    '--force-exclude' 'python/build/*'
    '--force-exclude' 'python/ray/core/src/ray/gcs/*'
    '--force-exclude' 'python/ray/thirdparty_files/*'
    '--force-exclude' 'python/ray/_private/thirdparty/*'
)

GIT_LS_EXCLUDES=(
  ':(exclude)python/ray/cloudpickle/'
  ':(exclude)python/ray/_private/runtime_env/_clonevirtualenv.py'
)

JAVA_EXCLUDES=(
  'java/api/src/main/java/io/ray/api/ActorCall.java'
  'java/api/src/main/java/io/ray/api/PyActorCall.java'
  'java/api/src/main/java/io/ray/api/RayCall.java'
)

JAVA_EXCLUDES_REGEX=""
for f in "${JAVA_EXCLUDES[@]}"; do
  JAVA_EXCLUDES_REGEX="$JAVA_EXCLUDES_REGEX|(${f//\//\/})"
done
JAVA_EXCLUDES_REGEX=${JAVA_EXCLUDES_REGEX#|}

# TODO(barakmich): This should be cleaned up. I've at least excised the copies
# of these arguments to this location, but the long-term answer is to actually
# make a flake8 config file
FLAKE8_PYX_IGNORES="--ignore=C408,E121,E123,E126,E211,E225,E226,E227,E24,E704,E999,W503,W504,W605"

shellcheck_scripts() {
  shellcheck "${SHELLCHECK_FLAGS[@]}" "$@"
}

# Runs mypy on each argument in sequence. This is different than running mypy
# once on the list of arguments.
mypy_on_each() {
    pushd python/ray
    for file in "$@"; do
       echo "Running mypy on $file"
       mypy ${MYPY_FLAGS[@]+"${MYPY_FLAGS[@]}"} "$file"
    done
    popd
}

isort_on_paths() {
    for path in "$@"; do
       echo "Running isort on files under $path"
       isort "$path"
    done
}

# Format specified files
format_files() {
    local shell_files=() python_files=() bazel_files=()

    local name
    for name in "$@"; do
      local base="${name%.*}"
      local suffix="${name#"${base}"}"

      local shebang=""
      read -r shebang < "${name}" || true
      case "${shebang}" in
        '#!'*)
          shebang="${shebang#/usr/bin/env }"
          shebang="${shebang%% *}"
          shebang="${shebang##*/}"
          ;;
      esac

      if [ "${base}" = "WORKSPACE" ] || [ "${base}" = "BUILD" ] || [ "${suffix}" = ".BUILD" ] || [ "${suffix}" = ".bazel" ] || [ "${suffix}" = ".bzl" ]; then
        bazel_files+=("${name}")
      elif [ -z "${suffix}" ] && [ "${shebang}" != "${shebang#python}" ] || [ "${suffix}" != "${suffix#.py}" ]; then
        python_files+=("${name}")
      elif [ -z "${suffix}" ] && [ "${shebang}" != "${shebang%sh}" ] || [ "${suffix}" != "${suffix#.sh}" ]; then
        shell_files+=("${name}")
      else
        echo "error: failed to determine file type: ${name}" 1>&2
        return 1
      fi
    done

    if [ 0 -lt "${#python_files[@]}" ]; then
      isort "${python_files[@]}"
      black "${python_files[@]}"
    fi

    if command -v shellcheck >/dev/null; then
      if shellcheck --shell=sh --format=diff - < /dev/null; then
        if [ 0 -lt "${#shell_files[@]}" ]; then
          local difference
          difference="$(shellcheck_scripts --format=diff "${shell_files[@]}" || true && printf "-")"
          difference="${difference%-}"
          printf "%s" "${difference}" | patch -p1
        fi
      else
        echo "error: this version of shellcheck does not support diffs"
      fi
    fi
}

format_all_scripts() {
    command -v flake8 &> /dev/null;
    HAS_FLAKE8=$?

    # Run isort before black to fix imports and let black deal with file format.
    echo "$(date)" "isort...."
    isort_on_paths "${ISORT_PATHS[@]}"
    echo "$(date)" "Black...."
    git ls-files -- '*.py' "${GIT_LS_EXCLUDES[@]}" | xargs -P 10 \
      black "${BLACK_EXCLUDES[@]}"
    echo "$(date)" "MYPY...."
    mypy_on_each "${MYPY_FILES[@]}"
    if [ $HAS_FLAKE8 ]; then
      echo "$(date)" "Flake8...."
      git ls-files -- '*.py' "${GIT_LS_EXCLUDES[@]}" | xargs -P 5 \
        flake8 --config=.flake8

      git ls-files -- '*.pyx' '*.pxd' '*.pxi' "${GIT_LS_EXCLUDES[@]}" | xargs -P 5 \
        flake8 --config=.flake8 "$FLAKE8_PYX_IGNORES"
    fi

    if command -v shellcheck >/dev/null; then
      local shell_files non_shell_files
      non_shell_files=($(git ls-files -- ':(exclude)*.sh'))
      shell_files=($(git ls-files -- '*.sh'))
      if [ 0 -lt "${#non_shell_files[@]}" ]; then
        shell_files+=($(git --no-pager grep -l -- '^#!\(/usr\)\?/bin/\(env \+\)\?\(ba\)\?sh' "${non_shell_files[@]}" || true))
      fi
      if [ 0 -lt "${#shell_files[@]}" ]; then
        echo "$(date)" "shellcheck scripts...."
        shellcheck_scripts "${shell_files[@]}"
      fi
    fi
}

# Format all files, and print the diff to stdout for travis.
# Mypy is run only on files specified in the array MYPY_FILES.
format_all() {
    format_all_scripts "${@}"

    echo "$(date)" "clang-format...."
    if command -v clang-format >/dev/null; then
      git ls-files -- '*.cc' '*.h' '*.proto' "${GIT_LS_EXCLUDES[@]}" | xargs -P 5 clang-format -i
    fi

    echo "$(date)" "format java...."
    if command -v java >/dev/null & [ -f "$GOOGLE_JAVA_FORMAT_JAR" ]; then
      git ls-files -- '*.java' "${GIT_LS_EXCLUDES[@]}" | sed -E "\:$JAVA_EXCLUDES_REGEX:d" | xargs -P 5 java -jar "$GOOGLE_JAVA_FORMAT_JAR" -i
    fi

    echo "$(date)" "done!"
}

# Format files that differ from main branch. Ignores dirs that are not slated
# for autoformat yet.
format_changed() {
    # The `if` guard ensures that the list of filenames is not empty, which
    # could cause the formatter to receive 0 positional arguments, making
    # Black error.
    #
    # `diff-filter=ACRM` and $MERGEBASE is to ensure we only format files that
    # exist on both branches.
    MERGEBASE="$(git merge-base upstream/master HEAD)"

    if ! git diff --diff-filter=ACRM --quiet --exit-code "$MERGEBASE" -- '*.py' &>/dev/null; then
        git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.py' | xargs -P 5 \
            isort
    fi

    if ! git diff --diff-filter=ACRM --quiet --exit-code "$MERGEBASE" -- '*.py' &>/dev/null; then
        git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.py' | xargs -P 5 \
            black "${BLACK_EXCLUDES[@]}"
        if which flake8 >/dev/null; then
            git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.py' | xargs -P 5 \
                 flake8 --config=.flake8
        fi
    fi

    if ! git diff --diff-filter=ACRM --quiet --exit-code "$MERGEBASE" -- '*.pyx' '*.pxd' '*.pxi' &>/dev/null; then
        if which flake8 >/dev/null; then
            git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.pyx' '*.pxd' '*.pxi' | xargs -P 5 \
                 flake8 --config=.flake8 "$FLAKE8_PYX_IGNORES"
        fi
    fi

    if which clang-format >/dev/null; then
        if ! git diff --diff-filter=ACRM --quiet --exit-code "$MERGEBASE" -- '*.cc' '*.h' &>/dev/null; then
            git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.cc' '*.h' | xargs -P 5 \
                 clang-format -i
        fi
    fi

    if command -v java >/dev/null & [ -f "$GOOGLE_JAVA_FORMAT_JAR" ]; then
       if ! git diff --diff-filter=ACRM --quiet --exit-code "$MERGEBASE" -- '*.java' &>/dev/null; then
            git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.java' | sed -E "\:$JAVA_EXCLUDES_REGEX:d" | xargs -P 5 java -jar "$GOOGLE_JAVA_FORMAT_JAR" -i
        fi
    fi

    if command -v shellcheck >/dev/null; then
        local shell_files non_shell_files
        non_shell_files=($(git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- ':(exclude)*.sh'))
        shell_files=($(git diff --name-only --diff-filter=ACRM "$MERGEBASE" -- '*.sh'))
        if [ 0 -lt "${#non_shell_files[@]}" ]; then
            shell_files+=($(git --no-pager grep -l -- '^#!\(/usr\)\?/bin/\(env \+\)\?\(ba\)\?sh' "${non_shell_files[@]}" || true))
        fi
        if [ 0 -lt "${#shell_files[@]}" ]; then
            shellcheck_scripts "${shell_files[@]}"
        fi
    fi
}

# This flag formats individual files. --files *must* be the first command line
# arg to use this option.
if [ "${1-}" == '--files' ]; then
    format_files "${@:2}"
# If `--all` or `--scripts` are passed, then any further arguments are ignored.
# Format the entire python directory and other scripts.
elif [ "${1-}" == '--all-scripts' ]; then
    format_all_scripts "${@}"
    if [ -n "${FORMAT_SH_PRINT_DIFF-}" ]; then git --no-pager diff; fi
# Format the all Python, C++, Java and other script files.
elif [ "${1-}" == '--all' ]; then
    format_all "${@}"
    if [ -n "${FORMAT_SH_PRINT_DIFF-}" ]; then git --no-pager diff; fi
else
    # Add the upstream remote if it doesn't exist
    if ! git remote -v | grep -q upstream; then
        git remote add 'upstream' 'https://github.com/ray-project/ray.git'
    fi

    # Only fetch master since that's the branch we're diffing against.
    git fetch upstream master || true

    # Format only the files that changed in last commit.
    format_changed
fi

check_docstyle

# Ensure import ordering
# Make sure that for every import psutil; import setproctitle
# There's a import ray above it.

PYTHON_EXECUTABLE=${PYTHON_EXECUTABLE:-python}

$PYTHON_EXECUTABLE ci/lint/check_import_order.py . -s ci -s python/ray/thirdparty_files -s python/build -s lib

if ! git diff --quiet &>/dev/null; then
    echo 'Reformatted changed files. Please review and stage the changes.'
    echo 'Files updated:'
    echo

    git --no-pager diff --name-only

    exit 1
fi
