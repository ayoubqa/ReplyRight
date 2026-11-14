#!/usr/bin/env python3
"""A heuristic cross-reference check for the Swift sources.

This is NOT a compiler and proves nothing about types. It exists because the
project is sometimes edited on machines without Xcode, and it catches the
mistakes that are cheap to catch from text alone:

  1. a project type that is used but never declared (a typo, a deleted view)
  2. a member read from one of the project's own namespaces or models that
     does not exist (Color.rrSomething, app.someProperty, RRSpace.huge)
  3. a call to a project initialiser whose argument labels match no
     initialiser of that type

Run it from anywhere:  python3 ios/scripts/check_swift_references.py
It exits non-zero when it finds something. Xcode remains the judge.
"""
from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIRS = ["ReplyRight", "ReplyRightKeyboard", "ReplyRightShare", "Packages/ReplyRightKit/Sources", "ReplyRightUITests",
               "Packages/ReplyRightKit/Tests"]


def strip(code: str) -> str:
    """Blanks out comments and string contents, keeping offsets and newlines."""
    out = []
    i, n = 0, len(code)
    while i < n:
        c = code[i]
        two = code[i:i + 2]
        if two == "//":
            j = code.find("\n", i)
            j = n if j == -1 else j
            out.append(" " * (j - i))
            i = j
        elif two == "/*":
            j = code.find("*/", i + 2)
            j = n if j == -1 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in code[i:j]))
            i = j
        elif two == '#"':
            j = code.find('"#', i + 2)
            j = n if j == -1 else j + 2
            out.append('"' + "".join(ch if ch == "\n" else " " for ch in code[i + 1:j - 1]) + '"')
            i = j
        elif code[i:i + 3] == '"""':
            j = code.find('"""', i + 3)
            j = n if j == -1 else j + 3
            out.append('"' + "".join(ch if ch == "\n" else " " for ch in code[i + 1:j - 1]) + '"')
            i = j
        elif c == '"':
            j = i + 1
            depth = 0
            buf = ['"']
            while j < n:
                ch = code[j]
                if ch == "\\" and j + 1 < n and code[j + 1] == "(":
                    # Interpolation: keep the expression so references inside it are checked.
                    depth = 1
                    k = j + 2
                    buf.append("  ")
                    while k < n and depth > 0:
                        if code[k] == "(":
                            depth += 1
                        elif code[k] == ")":
                            depth -= 1
                            if depth == 0:
                                break
                        buf.append(code[k] if code[k] != '"' else " ")
                        k += 1
                    buf.append(" ")
                    j = k + 1
                    continue
                if ch == "\\":
                    buf.append("  ")
                    j += 2
                    continue
                if ch == '"':
                    break
                buf.append(" " if ch != "\n" else "\n")
                j += 1
            buf.append('"')
            out.append("".join(buf))
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


TYPE_DECL = re.compile(r"\b(struct|class|enum|protocol|actor|extension)\s+([A-Z]\w*(?:\.[A-Z]\w*)*)")


class TypeInfo:
    def __init__(self, name: str):
        self.name = name
        self.kind = "struct"
        self.members: set[str] = set()
        self.cases: set[str] = set()
        self.inits: list[list[tuple[str, bool]]] = []  # (label, has_default)
        self.stored: list[tuple[str, bool, bool]] = []  # (name, has_default, in_memberwise)
        self.has_explicit_init = False
        self.declared = False  # False when only extensions were seen (an SDK type)
        self.inherits = ""


def match_brace(code: str, open_index: int) -> int:
    depth = 0
    for i in range(open_index, len(code)):
        if code[i] == "{":
            depth += 1
        elif code[i] == "}":
            depth -= 1
            if depth == 0:
                return i
    return len(code) - 1


def split_params(text: str) -> list[str]:
    parts, depth, current = [], 0, []
    for ch in text.replace("->", "\u2192"):
        if ch in "([{<":
            depth += 1
        elif ch in ")]}>":
            depth -= 1
        if ch == "," and depth == 0:
            parts.append("".join(current))
            current = []
        else:
            current.append(ch)
    if "".join(current).strip():
        parts.append("".join(current))
    return parts


def parse_signature(params: str) -> list[tuple[str, bool]]:
    result = []
    for raw in split_params(params):
        piece = raw.strip()
        if not piece:
            continue
        head = piece.split(":")[0].strip()
        head = re.sub(r"@\w+(\([^)]*\))?\s*", "", head)
        names = head.split()
        label = names[0] if names else "_"
        result.append((label, "=" in piece.split(":", 1)[-1] if ":" in piece else False))
    return result


def top_level_body(body: str) -> str:
    """Returns the body with nested braces blanked, so only direct members remain."""
    out, depth = [], 0
    for ch in body:
        if ch == "{":
            depth += 1
            out.append("{" if depth == 1 else " ")
        elif ch == "}":
            out.append("}" if depth == 1 else " ")
            depth -= 1
        else:
            out.append(ch if depth == 0 or ch == "\n" else " ")
    return "".join(out)


def collect(code: str, types: dict[str, TypeInfo], prefix: str = "") -> None:
    pos = 0
    while True:
        m = TYPE_DECL.search(code, pos)
        if not m:
            return
        brace = code.find("{", m.end())
        line_end = code.find("\n", m.end())
        if brace == -1 or (0 <= line_end < brace and "where" not in code[m.end():brace] and code[m.end():brace].count("\n") > 3):
            pos = m.end()
            continue
        end = match_brace(code, brace)
        kind, name = m.group(1), m.group(2)
        full = name if kind == "extension" else (f"{prefix}{name}" if prefix else name)
        short = full.split(".")[-1]
        info = types.setdefault(short, TypeInfo(short))
        if kind != "extension":
            info.kind = kind
            info.declared = True
            clause = code[m.end():brace]
            info.inherits = clause.split(":", 1)[1].strip() if ":" in clause else ""
        body = code[brace + 1:end]
        direct = top_level_body(body)

        for dm in re.finditer(r"(?m)^\s*((?:@\w+(?:\([^)]*\))?\s+)*)((?:(?:public|private|fileprivate|internal|static|final|override|mutating|nonisolated|lazy|weak|unowned|private\(set\)|public private\(set\)|class|indirect)\s+)*)(var|let|func|case|init|typealias|subscript)\b\s*([^\n]*)", direct):
            attrs, mods, keyword, rest = dm.group(1), dm.group(2), dm.group(3), dm.group(4)
            if keyword in ("var", "let"):
                nm = re.match(r"(\w+)", rest)
                if not nm:
                    continue
                info.members.add(nm.group(1))
                is_static = "static" in mods or "class" in mods.split()
                tail = rest[nm.end():]
                computed = keyword == "var" and re.search(r"\{\s*$", tail.strip()) is not None and "=" not in tail
                if not is_static and not computed and info.kind in ("struct", "class"):
                    # An optional `var` starts as nil without being given a value.
                    optional = keyword == "var" and re.search(r":\s*[^=]*\?\s*(=|$)", tail) is not None
                    has_default = "=" in tail or optional
                    wrapper = attrs.strip()
                    excluded = (keyword == "let" and has_default) or wrapper.startswith(("@Environment", "@FocusState", "@ScaledMetric", "@ObservationIgnored", "@AppStorage"))
                    if "private" in mods and wrapper.startswith("@State"):
                        excluded = True
                    info.stored.append((nm.group(1), has_default or wrapper.startswith("@State"), not excluded))
            elif keyword == "func":
                nm = re.match(r"(\w+)", rest)
                if nm:
                    info.members.add(nm.group(1))
            elif keyword == "typealias":
                nm = re.match(r"(\w+)", rest)
                if nm:
                    info.members.add(nm.group(1))
            elif keyword == "case" and info.kind == "enum":
                for cm in re.finditer(r"(?:^|,)\s*(\w+)", re.sub(r"\([^)]*\)", "", rest.split("//")[0])):
                    name_ = cm.group(1)
                    info.cases.add(name_)
                    info.members.add(name_)
            elif keyword == "init":
                info.has_explicit_init = True

        # Explicit initialisers, read from the full body because parameters may span lines.
        for im in re.finditer(r"\binit\??\s*(?:<[^>]*>)?\s*\(", direct):
            start = im.end()
            depth, j = 1, start
            while j < len(direct) and depth:
                depth += direct[j] == "("
                depth -= direct[j] == ")"
                j += 1
            info.inits.append(parse_signature(direct[start:j - 1]))

        collect(body, types, prefix=f"{full}.")
        pos = brace + 1 if kind == "extension" else end


def load() -> tuple[dict[str, str], dict[str, TypeInfo]]:
    files: dict[str, str] = {}
    for directory in SOURCE_DIRS:
        for path in sorted((ROOT / directory).rglob("*.swift")):
            files[str(path.relative_to(ROOT))] = strip(path.read_text())
    types: dict[str, TypeInfo] = {}
    for code in files.values():
        collect(code, types)
    return files, types


# Names from Apple frameworks and the standard library that appear in this project.
SDK = set("""
Any AnyObject AnyView App Array AttributedString Binding Bool Bundle Button ButtonStyle ButtonStyleConfiguration Calendar
Canvas Capsule CGAffineTransform CGFloat CGImageSourceCreateThumbnailAtIndex CGImageSourceCreateWithData CGPoint CGRect CGSize
CFData CFDictionary CFError CFString CFURL Character Circle Codable CodingKey CodingKeys Color ColorScheme Comparable Configuration
Content Context CTFontManagerRegisterFontsForURL Data Date DateFormatter Decodable Decoder Dictionary Divider Double EdgeInsets
EmptyView Encodable Encoder Environment EnvironmentValues Equatable Error FileManager FocusState Font ForEach Foundation
GeometryReader GridItem Group HStack Hashable HTTPURLResponse Identifiable Image ImageIO Int Int64 ISO8601DateFormatter
JSONDecoder JSONEncoder JSONSerialization Label Layout LazyVGrid LinearGradient Link List Locale MainActor Menu NavigationLink
NavigationStack NSAttributedString NSItemProvider NSLock NSObject NSRange NSString Never Notification NotificationCenter
Observable Observation ObservationIgnored Optional Path PhotosPicker PhotosPickerItem PhotosUI Picker ProcessInfo ProgressView
ProposedViewSize RadialGradient RandomAccessCollection Range Rectangle RectangleCornerRadii Result RoundedRectangle
ScaledMetric Scene ScrollView ScrollViewReader SecureField Self Sendable Set Shape ShareLink Spacer State StateObject
StoreKit String Subviews SwiftUI Task Text TextEditor TextField TimeInterval Timer Toggle ToolbarItem ToolbarItemGroup
Transaction UInt UInt32 UInt64 UInt8 URL URLError URLRequest URLResponse URLSession URLSessionConfiguration UUID
UnevenRoundedRectangle Unmanaged UserDefaults VStack View ViewBuilder ViewModifier Void WindowGroup ZStack Bindable
UIActivityViewController UIApplication UIBezierPath UIButton UIColor UIControl UIEdgeInsets UIEvent UIFont UIFontDescriptor
UIFontMetrics UIGraphicsImageRenderer UIGraphicsImageRendererFormat UIHostingController UIImage UIImageView
UIImpactFeedbackGenerator UIInputView UIInputViewController UIKit UILabel UILongPressGestureRecognizer UINavigationBar
UINavigationBarAppearance UINotificationFeedbackGenerator UIPasteboard UIScreen UIScrollView
UISelectionFeedbackGenerator UIStackView UITabBar UITabBarAppearance UITextDocumentProxy UITextInput UITextInputTraits
UITraitCollection UIView UIViewController UIViewControllerRepresentable UIDevice UIGestureRecognizer UITapGestureRecognizer
UIPanGestureRecognizer UIResponder UIWindow UITextContentType UIKeyboardType UIReturnKeyType UIImageSymbolConfiguration
UIAction UIMenu UIActivityIndicatorView UITextAutocapitalizationType UIKeyboardAppearance UIUserInterfaceStyle
UIInputViewAudioFeedback UILayoutGuide UILayoutPriority UIAccessibility UIAccessibilityTraits NSLayoutConstraint
NSLayoutDimension NSLayoutXAxisAnchor NSLayoutYAxisAnchor CALayer CAShapeLayer CABasicAnimation CATransaction CGPath CGColor
CGMutablePath CACurrentMediaTime CAMediaTimingFunction DispatchQueue DispatchTime DispatchWorkItem OperationQueue
XCTestCase XCTAssertEqual XCTAssertTrue XCTAssertFalse XCTAssertNil XCTAssertNotNil XCTUnwrap XCTFail XCUIApplication
XCTAssertThrowsError XCTAssertNoThrow XCTAssertNotEqual XCTAssertGreaterThan XCTAssertLessThan XCTAssertLessThanOrEqual
XCTAssertGreaterThanOrEqual XCUIElement XCTSkip XCTSkipIf XCTest XCTestExpectation UNUserNotificationCenter
Product VerificationResult SubscriptionStoreView StoreKitError Storefront AppStore PurchaseResult RenewalInfo
SecItemAdd SecItemCopyMatching SecItemDelete SecItemUpdate CFTypeRef OSStatus KeyPath WritableKeyPath Mirror
CancellationError LocalizedError CustomStringConvertible CaseIterable RawRepresentable Sequence Collection IndexSet
Animation AnyTransition Transaction Angle Alignment Axis Edge HorizontalAlignment VerticalAlignment TextAlignment
ContentMode ContentSizeCategory DynamicTypeSize Visibility ToolbarItemPlacement NavigationPath TabView Section Form
Gradient UnitPoint Material ShapeStyle InsettableShape AnyShape StrokeStyle Namespace Substring ArraySlice Slice
CharacterSet NumberFormatter Measurement Decimal NSNumber NSError NSCoding NSExtensionItem NSExtensionContext
TimeZone RelativeDateTimeFormatter UITextChecker UILexicon UILexiconEntry ContentUnavailableView ViewThatFits NSPredicate
XCTWaiter XCTNSPredicateExpectation
UTType UniformTypeIdentifiers Transferable DataRepresentation FileRepresentation CoreTransferable PersistentIdentifier
CoreText CTFontManagerScope LosslessStringConvertible ExpressibleByStringLiteral OptionSet StaticString AnyHashable
ObservableObject Published EnvironmentObject AppStorage SceneStorage UIApplicationDelegate ScenePhase
Element Key Value Index Iterator Body Output Failure Wrapped Success Input Response Payload Option Schema T U
CGImageSource CGImage CIImage SwiftUICore Combine Dispatch os Darwin Security XCUIElementQuery Never
CFTimeInterval CheckedContinuation FoundationNetworking NSCoder NSDecimalNumber NSDirectionalEdgeInsets NSSecureCoding
RunLoop UIConfigurationTextAttributesTransformer UIListContentConfiguration UIBackgroundConfiguration Selector
""".split())


def main() -> int:
    files, types = load()
    problems: list[str] = []
    declared = set(types)

    def line_of(code: str, index: int) -> int:
        return code.count("\n", 0, index) + 1

    # 1. Types that are used but not declared.
    unknown: dict[str, list[str]] = defaultdict(list)
    for path, code in files.items():
        for m in re.finditer(r"(?<![\w.])([A-Z][A-Za-z0-9]+)\b(?=\s*[(<.{]|\s*$|\s*[,)\]?!:>=])", code):
            name = m.group(1)
            if name in declared or name in SDK or name.isupper():
                continue
            before = code[max(0, m.start() - 40):m.start()]
            # Generic parameters declared right here, e.g. "func f<Value: Encodable>".
            if re.search(r"<[^>]*$", before) or re.search(r"\b(associatedtype|typealias)\s+$", before):
                continue
            unknown[name].append(f"{path}:{line_of(code, m.start())}")
    generic_names = set()
    for code in files.values():
        for g in re.finditer(r"<([^<>()]*)>", code):
            for part in g.group(1).split(","):
                token = part.split(":")[0].strip()
                if re.fullmatch(r"[A-Z]\w*", token):
                    generic_names.add(token)
    for name, places in sorted(unknown.items()):
        if name in generic_names:
            continue
        problems.append(f"unknown type or value '{name}' at {places[0]}" + (f" (+{len(places) - 1} more)" if len(places) > 1 else ""))

    # 2. Members of the project's own namespaces and models.
    def members(type_name: str) -> set[str]:
        return types[type_name].members if type_name in types else set()

    color_members = members("Color")
    namespaces = ["RRSpace", "RRRadius", "Palette", "Microcopy", "AppConfig", "RRFonts", "Haptics", "RequestLimits",
                  "BrandGeometry", "KeyboardTheme", "ServerFailure", "VoiceLearning", "ConversationText", "ScreenshotPreparer",
                  "InstallIdentity", "AppGroup", "DiagnosticsLog", "ProfilePhoto"]
    for path, code in files.items():
        for m in re.finditer(r"\bColor\.(rr\w+)", code):
            if m.group(1) not in color_members:
                problems.append(f"{path}:{line_of(code, m.start())}: Color.{m.group(1)} is not defined")
        for space in namespaces:
            known = members(space)
            if not known:
                continue
            for m in re.finditer(rf"(?<![\w.]){space}\.(\w+)", code):
                if m.group(1) not in known and m.group(1) not in ("self", "shared", "init"):
                    problems.append(f"{path}:{line_of(code, m.start())}: {space}.{m.group(1)} is not defined")
        text_styles = types["RRTextStyle"].cases if "RRTextStyle" in types else set()
        for m in re.finditer(r"\.rrText\(\.(\w+)\)|style:\s*\.(\w+)\)", code):
            style = m.group(1) or m.group(2)
            if m.group(1) and style not in text_styles:
                problems.append(f"{path}:{line_of(code, m.start())}: .rrText(.{style}) is not a text style")

    # Objects reached through well-known variable names in the app target.
    chains = {
        r"\bapp\.(\w+)": "AppModel",
        r"\bapp\.compose\.(\w+)": "ComposeModel",
        r"\bcompose\.(\w+)": "ComposeModel",
        r"\bcoach\.(\w+)": "CoachModel",
        r"\bboard\.(\w+)": "SuggestionBoard",
        r"\bapp\.settings\.(\w+)": "AppSettings",
        r"\bapp\.store\.(\w+)": "SharedStore",
        r"\bstore\.(\w+)": "SharedStore",
        r"\bapp\.backend\.(\w+)": "BackendTarget",
        r"\bapp\.connection\.(\w+)": "ConnectionState",
        r"\bapp\.purchases\.(\w+)": "StoreService",
        r"\bapp\.api\.(\w+)": "APIClient",
        r"\bapp\.voice\.(\w+)": "VoiceProfile",
    }
    for path, code in files.items():
        if not path.startswith(("ReplyRight/", "ReplyRightShare/", "ReplyRightKeyboard/")):
            continue
        for pattern, type_name in chains.items():
            known = members(type_name)
            if not known:
                continue
            for m in re.finditer(pattern, code):
                name = m.group(1)
                if pattern.startswith(r"\bstore") and not re.search(r"\b(let|var)\s+store\b|store:\s*SharedStore", code):
                    continue
                if name not in known and name not in ("self", "init"):
                    problems.append(f"{path}:{line_of(code, m.start())}: {type_name} has no member '{name}'")

    # 3. Initialiser labels of project types.
    for path, code in files.items():
        for m in re.finditer(r"(?<![\w.])([A-Z]\w+)\(", code):
            name = m.group(1)
            info = types.get(name)
            if info is None or not info.declared or info.kind not in ("struct", "class"):
                continue
            # Subclasses of framework classes inherit initialisers this script cannot see.
            if info.kind == "class" and re.match(r"(UI|NS|XC)", info.inherits):
                continue
            before = code[max(0, m.start() - 12):m.start()]
            if re.search(r"\b(struct|class|enum|func|extension|init)\s+$", before):
                continue
            start = m.end()
            depth, j = 1, start
            while j < len(code) and depth:
                depth += code[j] in "([{"
                depth -= code[j] in ")]}"
                j += 1
            args = split_params(code[start:j - 1])
            labels = []
            for arg in args:
                lm = re.match(r"\s*(\w+)\s*:(?!:)", arg)
                labels.append(lm.group(1) if lm else "_")
            signatures = list(info.inits)
            if not info.has_explicit_init:
                if info.kind == "class":
                    signatures.append([])
                else:
                    signatures.append([(n, d) for n, d, included in info.stored if included])
            if not signatures:
                continue

            def fits(signature: list[tuple[str, bool]]) -> bool:
                position = 0
                for label in labels:
                    while position < len(signature) and signature[position][0] != label:
                        if not signature[position][1]:
                            # A trailing closure may fill the last required parameter.
                            return False
                        position += 1
                    if position == len(signature):
                        return False
                    position += 1
                remaining = [s for s in signature[position:] if not s[1]]
                return len(remaining) <= 1  # one required parameter may be a trailing closure

            if not any(fits(sig) for sig in signatures):
                shown = ", ".join(f"{l}:" for l in labels) or "no arguments"
                problems.append(f"{path}:{line_of(code, m.start())}: {name}({shown}) matches no initialiser")

    problems.extend(check_switches(files))

    for problem in problems:
        print(problem)
    print(f"{len(files)} files, {len(types)} project types, {len(problems)} possible problems")
    return 1 if problems else 0


# ---------------------------------------------------------------- switches

def collect_enums(files: dict[str, str]) -> tuple[dict[str, set[str]], list[tuple[str, int, int, str]]]:
    """Every project enum by full name with its cases, and where each enum's body sits."""
    enums: dict[str, set[str]] = {}
    spans: list[tuple[str, int, int, str]] = []  # (path, start, end, full name)

    def walk(path: str, code: str, offset: int, prefix: str) -> None:
        pos = 0
        while True:
            m = re.search(r"\b(struct|class|enum|actor|extension)\s+([A-Z]\w*(?:\.[A-Z]\w*)*)", code[pos:])
            if not m:
                return
            start = pos + m.start()
            brace = code.find("{", pos + m.end())
            if brace == -1:
                return
            end = match_brace(code, brace)
            kind, name = m.group(1), m.group(2)
            full = name if kind == "extension" else (f"{prefix}{name}" if prefix else name)
            body = code[brace + 1:end]
            if kind == "enum":
                cases = enums.setdefault(full, set())
                for line in top_level_body(body).split("\n"):
                    cm = re.match(r"\s*(?:indirect\s+)?case\s+(.*)", line)
                    if cm:
                        for item in split_params(cm.group(1)):
                            im = re.match(r"\s*(\w+)", item)
                            if im:
                                cases.add(im.group(1))
            if kind in ("enum", "extension"):
                spans.append((path, offset + brace, offset + end, full))
            walk(path, body, offset + brace + 1, f"{full}.")
            pos = end + 1

    for path, code in files.items():
        walk(path, code, 0, "")
    return enums, spans


def case_patterns(body: str) -> list[str]:
    """The pattern of each top-level `case` in a switch body, even when it spans lines."""
    patterns = []
    for m in re.finditer(r"(?m)^\s*case\b", body):
        depth, i = 0, m.end()
        while i < len(body):
            ch = body[i]
            if ch in "([":
                depth += 1
            elif ch in ")]":
                depth -= 1
            elif ch == ":" and depth == 0 and body[i + 1:i + 2] != ":" and body[i - 1:i] != ":":
                break
            i += 1
        patterns.append(body[m.end():i])
    return patterns


def check_switches(files: dict[str, str]) -> list[str]:
    """Case labels must belong to the type switched on, and a switch without
    `default` must cover every case of that type."""
    enums, spans = collect_enums(files)
    problems: list[str] = []
    for path, code in files.items():
        for m in re.finditer(r"\bswitch\s+([^{\n]+?)\s*\{", code):
            subject = m.group(1).strip()
            brace = m.end() - 1
            end = match_brace(code, brace)
            body = top_level_body(code[brace + 1:end])
            line = code.count("\n", 0, m.start()) + 1
            labels: list[str] = []
            has_default = bool(re.search(r"(?m)^\s*(?:@unknown\s+)?default\s*:", body))
            simple = True
            for pattern in case_patterns(body):
                pattern = re.sub(r"\bwhere\b[\s\S]*$", "", pattern)
                for item in split_params(pattern):
                    item = re.sub(r"^\s*(?:let|var)\s+", "", item).strip()
                    im = re.match(r"\.(\w+)", item)
                    if not im:
                        simple = False
                        break
                    labels.append(im.group(1))
                if not simple:
                    break
            if not simple or not labels:
                continue
            label_set = set(labels)
            # `.none` and `.some` may be Optional's own cases, in a switch over an optional enum.
            if label_set & {"none", "some"} and not any(label_set <= cases for cases in enums.values()):
                label_set -= {"none", "some"}
                has_default = has_default or "none" in labels
                if not label_set:
                    continue

            if subject == "self":
                owners = [full for (p, a, b, full) in spans if p == path and a < m.start() < b]
                owner = owners[-1] if owners else None
                candidates = [owner] if owner in enums else []
            else:
                candidates = [name for name, cases in enums.items() if label_set <= cases]
                if not candidates:
                    overlap = sorted(
                        ((len(label_set & cases), name) for name, cases in enums.items() if len(label_set & cases) >= 2),
                        reverse=True,
                    )
                    # A system enum can share a few case names with a project enum, so only report a near match.
                    if overlap and overlap[0][0] * 4 >= len(label_set) * 3:
                        name = overlap[0][1]
                        missing = sorted(label_set - enums[name])
                        problems.append(f"{path}:{line}: switch {subject}: {', '.join('.' + x for x in missing)} are not cases of {name}")
                    continue

            for name in candidates:
                cases = enums[name]
                stray = sorted(label_set - cases)
                if stray:
                    problems.append(f"{path}:{line}: switch {subject}: {', '.join('.' + x for x in stray)} are not cases of {name}")
                elif not has_default and len(candidates) == 1 and cases - label_set:
                    uncovered = sorted(cases - label_set)
                    problems.append(f"{path}:{line}: switch {subject} over {name} has no default and misses {', '.join('.' + x for x in uncovered)}")
    return problems


if __name__ == "__main__":
    sys.exit(main())
