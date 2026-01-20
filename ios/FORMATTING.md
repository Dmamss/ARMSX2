# Code Formatting Guide

This document explains the code formatting setup for ARMSX2 iOS project.

## Overview

ARMSX2 iOS uses **clang-format** to ensure consistent code style across all Objective-C and Objective-C++ files. The configuration follows Apple/LLVM coding standards with minor customizations for readability.

## What is Formatted

**Formatted files:**
- `*.h` - Header files
- `*.m` - Objective-C implementation files
- `*.mm` - Objective-C++ implementation files

**Not formatted:**
- `*.swift` - Swift files (use SwiftLint separately if needed)
- `*.md` - Markdown documentation
- Build artifacts in `build/`, `DerivedData/`

## Style Rules

### Key Formatting Rules

**Indentation:**
- 4 spaces (no tabs)
- Continuation indent: 4 spaces

**Line Length:**
- Maximum 120 characters
- Comments are reflowed to fit

**Braces:**
- Opening brace on same line (K&R style)
```objc
- (void)doSomething {
    if (condition) {
        // code
    }
}
```

**Pointers:**
- Pointer aligned to the right (Apple style)
```objc
NSString *name;  // ✓ Correct
NSString* name;  // ✗ Wrong
```

**Spacing:**
- Space after `if`, `for`, `while`, `switch`
- No space after function/method name
```objc
if (condition) {  // ✓ Correct
if(condition) {   // ✗ Wrong

[self doSomething];      // ✓ Correct
[self doSomething] ;     // ✗ Wrong
```

**Objective-C Blocks:**
- 4-space indentation
```objc
dispatch_async(queue, ^{
    // code
});
```

**Method Declarations:**
```objc
- (instancetype)initWithName:(NSString *)name
                         age:(NSInteger)age
                     address:(NSString *)address;
```

## Quick Start

### 1. Install clang-format

**macOS (Homebrew):**
```bash
brew install clang-format
```

**Ubuntu/Debian:**
```bash
sudo apt-get install clang-format
```

**Windows:**
Download from [LLVM releases](https://llvm.org/builds/)

**Verify installation:**
```bash
clang-format --version
# Should show version 14 or higher
```

### 2. Format Your Code

**Format all iOS files:**
```bash
cd ios
./scripts/format-code.sh
```

**Check formatting without modifying files:**
```bash
cd ios
./scripts/format-code.sh check
```

**Format a single file:**
```bash
clang-format -i ARMSX2/JIT/JITManager.mm
```

**Preview changes without modifying:**
```bash
clang-format ARMSX2/JIT/JITManager.mm | diff -u ARMSX2/JIT/JITManager.mm -
```

### 3. Set Up Pre-Commit Hook (Optional)

Automatically check formatting before each commit:

```bash
# From repository root
cp ios/scripts/pre-commit.hook .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

Now formatting will be checked before every commit. To bypass (not recommended):
```bash
git commit --no-verify
```

## IDE Integration

### Xcode

**Option 1: Use Script (Recommended)**

Add a build phase script:
1. Select your target in Xcode
2. Go to Build Phases
3. Add "New Run Script Phase"
4. Enter:
```bash
cd "${PROJECT_DIR}/ios"
./scripts/format-code.sh check
```

**Option 2: Clang-Format Plugin**

Install [ClangFormat-Xcode](https://github.com/travisjeffery/ClangFormat-Xcode):
```bash
brew install --cask clangformat-xcode
```

Then in Xcode: Editor → Clang Format → Format File

### VS Code

**Install extension:**
```bash
code --install-extension xaver.clang-format
```

**Configure (`.vscode/settings.json`):**
```json
{
  "editor.formatOnSave": true,
  "[objective-c]": {
    "editor.defaultFormatter": "xaver.clang-format"
  },
  "[objective-cpp]": {
    "editor.defaultFormatter": "xaver.clang-format"
  }
}
```

### CLion / AppCode

Settings → Editor → Code Style → Enable ClangFormat (with clangd)

## GitHub Actions

### Automatic Format Checking

Every push and pull request automatically checks code formatting via GitHub Actions.

**Workflow:** `.github/workflows/ios_build.yml`

**What it does:**
1. Finds all `.h`, `.m`, `.mm` files
2. Runs `clang-format --dry-run --Werror`
3. Fails the build if any file needs formatting
4. Shows diff of required changes

**If the check fails:**

The GitHub Actions log will show:
```
ERROR: ARMSX2/JIT/JITManager.mm needs formatting
Run: clang-format -i ARMSX2/JIT/JITManager.mm

Format check failed! Please run clang-format on the above files.

To fix all files at once:
  cd ios
  find ARMSX2 -type f \( -name '*.h' -o -name '*.m' -o -name '*.mm' \) -exec clang-format -i {} \;
```

**To fix:**
```bash
cd ios
./scripts/format-code.sh
git add ARMSX2
git commit --amend --no-edit
git push --force-with-lease
```

## Configuration

### .clang-format File

Location: `ios/.clang-format`

Key settings:
```yaml
BasedOnStyle: LLVM
Language: ObjC
IndentWidth: 4
ColumnLimit: 120
PointerAlignment: Right
BreakBeforeBraces: Attach
```

**To customize:**
1. Edit `ios/.clang-format`
2. Run `./scripts/format-code.sh` to reformat all files
3. Commit the changes

**Available options:**
See [Clang-Format Style Options](https://clang.llvm.org/docs/ClangFormatStyleOptions.html)

### Disabling Formatting

**For specific code sections:**
```objc
// clang-format off
NSArray *array = @[
    @"deliberately",
    @"formatted",
    @"this",
    @"way"
];
// clang-format on
```

**For entire file:**
Add to top of file:
```objc
// clang-format off
```

**Not recommended** unless you have a specific reason (e.g., generated code, lookup tables).

## Common Issues

### Issue: "clang-format: command not found"

**Solution:** Install clang-format (see Quick Start above)

### Issue: Different formatting between local and CI

**Cause:** Different clang-format versions

**Solution:** Ensure you're using clang-format 14+
```bash
clang-format --version
```

If you have an older version, update it:
```bash
# macOS
brew upgrade clang-format

# Ubuntu
sudo apt-get update
sudo apt-get install --only-upgrade clang-format
```

### Issue: Format check fails but file looks correct

**Cause:** Invisible whitespace characters

**Solution:**
```bash
# Show whitespace
cat -A ARMSX2/JIT/JITManager.mm

# Fix automatically
clang-format -i ARMSX2/JIT/JITManager.mm
```

### Issue: Xcode keeps reformatting my code differently

**Solution:** Disable Xcode's automatic formatting:
- Xcode → Preferences → Text Editing
- Uncheck "Enable automatic indentation"
- Use clang-format exclusively

### Issue: Pre-commit hook is slow

**Solution:** The hook only checks staged files. If still slow:
```bash
# Remove the hook
rm .git/hooks/pre-commit

# Format manually before committing
cd ios && ./scripts/format-code.sh && cd ..
git add ios/ARMSX2
git commit
```

## Best Practices

### 1. Format Before Committing

Always run format check before pushing:
```bash
cd ios
./scripts/format-code.sh check
```

### 2. Format Incrementally

Don't format all files at once in a feature branch. Instead:
- Format files you modify
- Include formatting in the same commit as the code change

### 3. Separate Formatting Commits (Initial Setup)

When first applying clang-format to a project:
```bash
cd ios
./scripts/format-code.sh
git add ARMSX2
git commit -m "Format iOS code with clang-format"
```

This makes it easy to review formatting vs. logic changes.

### 4. Use Format-on-Save

Configure your IDE to format on save. This ensures you never forget.

### 5. Review Formatting Changes

Before committing formatted code:
```bash
git diff ios/ARMSX2
```

Make sure only formatting changed, not logic.

## Examples

### Before and After

**Before (inconsistent):**
```objc
-(void)doSomething:(NSString*)name {
  if(name!=nil)
  {
    NSLog(@"Name: %@",name);
  }


  NSArray* items=@[@"a",@"b"];
}
```

**After (formatted):**
```objc
- (void)doSomething:(NSString *)name {
    if (name != nil) {
        NSLog(@"Name: %@", name);
    }

    NSArray *items = @[ @"a", @"b" ];
}
```

### Objective-C Block Formatting

**Before:**
```objc
dispatch_async(queue, ^{
NSLog(@"Task started");
[self doWork];
});
```

**After:**
```objc
dispatch_async(queue, ^{
    NSLog(@"Task started");
    [self doWork];
});
```

### Method Declaration Formatting

**Before:**
```objc
-(instancetype)initWithName:(NSString*)name age:(NSInteger)age address:(NSString*)address
{
    self=[super init];
    if(self){
        _name=name;
        _age=age;
        _address=address;
    }
    return self;
}
```

**After:**
```objc
- (instancetype)initWithName:(NSString *)name age:(NSInteger)age address:(NSString *)address {
    self = [super init];
    if (self) {
        _name = name;
        _age = age;
        _address = address;
    }
    return self;
}
```

## Scripts Reference

### format-code.sh

**Format all files:**
```bash
./scripts/format-code.sh
```

**Check without modifying:**
```bash
./scripts/format-code.sh check
```

**Output:**
- Green "OK" = file is properly formatted
- Yellow "formatted" = file was reformatted
- Red "NEEDS FORMATTING" = file needs formatting (check mode)

### pre-commit.hook

**Install:**
```bash
cp ios/scripts/pre-commit.hook .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

**Behavior:**
- Runs automatically on `git commit`
- Only checks staged iOS files
- Fails commit if formatting needed
- Can be bypassed with `--no-verify`

## Troubleshooting

### Get Help

**Check what would be formatted:**
```bash
cd ios
find ARMSX2 -type f \( -name "*.h" -o -name "*.m" -o -name "*.mm" \) ! -path "*/build/*"
```

**See formatting diff for a file:**
```bash
clang-format ARMSX2/JIT/JITManager.mm | diff -u ARMSX2/JIT/JITManager.mm -
```

**Format with verbose output:**
```bash
clang-format -i -verbose ARMSX2/JIT/JITManager.mm
```

**Validate .clang-format syntax:**
```bash
clang-format --dump-config ios/.clang-format > /dev/null
```

## Related Documentation

- [BUILD_STATUS_ANALYSIS.md](BUILD_STATUS_ANALYSIS.md) - Complete build system analysis
- [Clang-Format Documentation](https://clang.llvm.org/docs/ClangFormat.html)
- [LLVM Coding Standards](https://llvm.org/docs/CodingStandards.html)
- [Apple Coding Guidelines](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CodingGuidelines/)

## FAQ

**Q: Do I need to format Swift files?**
A: No, clang-format only handles Objective-C/C++. For Swift, use SwiftLint if desired.

**Q: Can I use a different style?**
A: Yes, edit `ios/.clang-format` and commit the changes.

**Q: Will this reformat the entire codebase?**
A: Only if you run `./scripts/format-code.sh`. The pre-commit hook only checks staged files.

**Q: What if I disagree with a formatting rule?**
A: Discuss with the team, then update `.clang-format` if everyone agrees.

**Q: Can I format just one function?**
A: Yes, use Xcode's "Format Selection" or select code and run clang-format with `-lines` option.

**Q: Does this slow down CI?**
A: No, format checking takes only ~5-10 seconds on CI.

---

**Questions?** Open an issue or ask in the team chat.
