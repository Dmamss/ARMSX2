#!/bin/bash
#
# format-code.sh - Format all Objective-C/C++ code in iOS project
#
# Usage:
#   ./scripts/format-code.sh          # Format all files
#   ./scripts/format-code.sh check    # Check formatting without modifying files
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if clang-format is installed
if ! command -v clang-format &> /dev/null; then
    echo -e "${RED}Error: clang-format is not installed${NC}"
    echo ""
    echo "Install it with:"
    echo "  macOS:   brew install clang-format"
    echo "  Ubuntu:  sudo apt-get install clang-format"
    echo "  Windows: Download from https://llvm.org/builds/"
    exit 1
fi

echo "clang-format version: $(clang-format --version)"
echo ""

# Change to iOS directory
cd "$IOS_DIR"

# Find all Objective-C/C++ files
echo "Finding Objective-C/C++ files..."
FILES=$(find ARMSX2 -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) ! -path "*/build/*" ! -path "*/DerivedData/*")
FILE_COUNT=$(echo "$FILES" | wc -l | tr -d ' ')

echo "Found $FILE_COUNT files to process"
echo ""

# Check mode or format mode
if [ "$1" == "check" ] || [ "$1" == "--check" ]; then
    echo -e "${YELLOW}Running in CHECK mode (no files will be modified)${NC}"
    echo ""

    FAILED=0
    FAILED_FILES=()

    for FILE in $FILES; do
        echo -n "Checking $FILE... "
        if clang-format --dry-run --Werror "$FILE" 2>/dev/null; then
            echo -e "${GREEN}OK${NC}"
        else
            echo -e "${RED}NEEDS FORMATTING${NC}"
            FAILED=1
            FAILED_FILES+=("$FILE")
        fi
    done

    echo ""
    if [ $FAILED -eq 1 ]; then
        echo -e "${RED}Format check failed!${NC}"
        echo ""
        echo "The following files need formatting:"
        for FILE in "${FAILED_FILES[@]}"; do
            echo "  - $FILE"
        done
        echo ""
        echo "To fix all files, run:"
        echo "  ./scripts/format-code.sh"
        echo ""
        echo "To see the diff:"
        for FILE in "${FAILED_FILES[@]}"; do
            echo "  clang-format $FILE | diff -u $FILE -"
        done
        exit 1
    else
        echo -e "${GREEN}All files are properly formatted!${NC}"
        exit 0
    fi
else
    echo -e "${GREEN}Running in FORMAT mode (files will be modified)${NC}"
    echo ""

    FORMATTED_COUNT=0

    for FILE in $FILES; do
        echo -n "Formatting $FILE... "

        # Create backup
        cp "$FILE" "$FILE.bak"

        # Format the file
        clang-format -i "$FILE"

        # Check if file changed
        if diff -q "$FILE" "$FILE.bak" >/dev/null 2>&1; then
            echo -e "${GREEN}no changes${NC}"
            rm "$FILE.bak"
        else
            echo -e "${YELLOW}formatted${NC}"
            rm "$FILE.bak"
            FORMATTED_COUNT=$((FORMATTED_COUNT + 1))
        fi
    done

    echo ""
    if [ $FORMATTED_COUNT -eq 0 ]; then
        echo -e "${GREEN}All files were already properly formatted!${NC}"
    else
        echo -e "${GREEN}Successfully formatted $FORMATTED_COUNT file(s)${NC}"
        echo ""
        echo "Review the changes with:"
        echo "  git diff ios/ARMSX2"
        echo ""
        echo "If you're happy with the changes, commit them:"
        echo "  git add ios/ARMSX2"
        echo "  git commit -m \"Format iOS code with clang-format\""
    fi
    exit 0
fi
