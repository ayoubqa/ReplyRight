#!/usr/bin/env python3
"""Generate ios/ReplyRight.xcodeproj from the files on disk.

Run it again whenever Swift files are added, removed or moved:

    python3 ios/scripts/generate_xcodeproj.py

The output is deterministic (object IDs are derived from names), so re-running
it without changes produces an identical project. Build settings that differ
per environment live in ios/Config/*.xcconfig, not here.

Targets
    ReplyRight           iOS app (SwiftUI)
    ReplyRightKeyboard   custom keyboard extension (UIKit)
    ReplyRightShare      share extension
    ReplyRightUITests    UI tests
plus the local Swift package Packages/ReplyRightKit (ReplyRightCore, ReplyRightUI).

`ios/project.yml` describes the same project for XcodeGen, as a fallback.
"""
from __future__ import annotations

import hashlib
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
PROJECT = ROOT / "ReplyRight.xcodeproj"
DEPLOYMENT_TARGET = "17.0"
PACKAGE_PATH = "Packages/ReplyRightKit"


def uid(*parts: str) -> str:
    """A stable 24-character object identifier."""
    return hashlib.md5("/".join(parts).encode()).hexdigest()[:24].upper()


def quote(value) -> str:
    text = str(value)
    if text and re.fullmatch(r"[A-Za-z0-9_./]+", text):
        return text
    escaped = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def render(value, indent: int) -> str:
    pad = "\t" * indent
    if isinstance(value, dict):
        lines = ["{"]
        for key, item in value.items():
            lines.append(f"{pad}\t{quote(key)} = {render(item, indent + 1)};")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, (list, tuple)):
        lines = ["("]
        for item in value:
            lines.append(f"{pad}\t{render(item, indent + 1)},")
        lines.append(f"{pad})")
        return "\n".join(lines)
    return quote(value)


FILE_TYPES = {
    ".swift": "sourcecode.swift",
    ".plist": "text.plist.xml",
    ".entitlements": "text.plist.entitlements",
    ".xcprivacy": "text.xml",
    ".xcassets": "folder.assetcatalog",
    ".xcconfig": "text.xcconfig",
    ".storekit": "text",
    ".md": "net.daringfireball.markdown",
}


class Project:
    def __init__(self) -> None:
        self.objects: dict[str, dict] = {}

    def add(self, identifier: str, isa: str, **fields) -> str:
        if identifier in self.objects:
            raise ValueError(f"duplicate object id for {isa}: {identifier}")
        self.objects[identifier] = {"isa": isa, **fields}
        return identifier

    # ---------------------------------------------------------------- files

    def file_ref(self, relative: pathlib.Path, name: str | None = None) -> str:
        """A reference to a file, with its path relative to the enclosing group."""
        identifier = uid("file", str(relative))
        if identifier not in self.objects:
            fields = {
                "lastKnownFileType": FILE_TYPES.get(relative.suffix, "text"),
                "path": name or relative.name,
                "sourceTree": "<group>",
            }
            self.add(identifier, "PBXFileReference", **fields)
        return identifier

    def group_for(self, directory: pathlib.Path) -> tuple[str, list[pathlib.Path]]:
        """Mirrors a directory as a group. Returns the group id and every file under it."""
        children: list[str] = []
        files: list[pathlib.Path] = []
        entries = sorted(directory.iterdir(), key=lambda p: (p.is_file(), p.name.lower()))
        for entry in entries:
            if entry.name.startswith("."):
                continue
            relative = entry.relative_to(ROOT)
            if entry.is_dir() and entry.suffix != ".xcassets":
                group, nested = self.group_for(entry)
                children.append(group)
                files.extend(nested)
            else:
                children.append(self.file_ref(relative))
                files.append(relative)
        identifier = self.add(
            uid("group", str(directory.relative_to(ROOT))),
            "PBXGroup",
            children=children,
            path=directory.name,
            sourceTree="<group>",
        )
        return identifier, files

    # ---------------------------------------------------------------- build settings

    def configuration_list(self, owner: str, debug: dict, release: dict, base: dict[str, str] | None = None) -> str:
        configs = []
        for name, settings in (("Debug", debug), ("Release", release)):
            fields = {"buildSettings": settings, "name": name}
            if base:
                fields["baseConfigurationReference"] = base[name]
            configs.append(self.add(uid("config", owner, name), "XCBuildConfiguration", **fields))
        return self.add(
            uid("configlist", owner),
            "XCConfigurationList",
            buildConfigurations=configs,
            defaultConfigurationIsVisible=0,
            defaultConfigurationName="Release",
        )


def build() -> str:
    project = Project()
    project_id = uid("project")

    # ---- Groups and files -------------------------------------------------
    config_group, _ = project.group_for(ROOT / "Config")
    base_configs = {
        "Debug": uid("file", "Config/Debug.xcconfig"),
        "Release": uid("file", "Config/Release.xcconfig"),
    }

    target_dirs = {
        "ReplyRight": ROOT / "ReplyRight",
        "ReplyRightKeyboard": ROOT / "ReplyRightKeyboard",
        "ReplyRightShare": ROOT / "ReplyRightShare",
        "ReplyRightUITests": ROOT / "ReplyRightUITests",
    }
    groups: dict[str, str] = {}
    files: dict[str, list[pathlib.Path]] = {}
    for name, directory in target_dirs.items():
        groups[name], files[name] = project.group_for(directory)

    package_ref = project.add(
        uid("file", PACKAGE_PATH),
        "PBXFileReference",
        lastKnownFileType="wrapper",
        name="ReplyRightKit",
        path=PACKAGE_PATH,
        sourceTree="<group>",
    )
    packages_group = project.add(
        uid("group", "Packages"), "PBXGroup", children=[package_ref], name="Packages", sourceTree="<group>"
    )
    storekit_ref = project.file_ref(pathlib.Path("ReplyRight.storekit"))

    products = {
        "ReplyRight": ("ReplyRight.app", "wrapper.application"),
        "ReplyRightKeyboard": ("ReplyRightKeyboard.appex", "wrapper.app-extension"),
        "ReplyRightShare": ("ReplyRightShare.appex", "wrapper.app-extension"),
        "ReplyRightUITests": ("ReplyRightUITests.xctest", "wrapper.cfbundle"),
    }
    product_refs = {
        name: project.add(
            uid("product", name),
            "PBXFileReference",
            explicitFileType=file_type,
            includeInIndex=0,
            path=path,
            sourceTree="BUILT_PRODUCTS_DIR",
        )
        for name, (path, file_type) in products.items()
    }
    products_group = project.add(
        uid("group", "Products"),
        "PBXGroup",
        children=list(product_refs.values()),
        name="Products",
        sourceTree="<group>",
    )
    main_group = project.add(
        uid("group", "main"),
        "PBXGroup",
        children=[
            groups["ReplyRight"],
            groups["ReplyRightKeyboard"],
            groups["ReplyRightShare"],
            groups["ReplyRightUITests"],
            packages_group,
            config_group,
            storekit_ref,
            products_group,
        ],
        sourceTree="<group>",
    )

    # ---- Swift package ----------------------------------------------------
    local_package = project.add(
        uid("package", PACKAGE_PATH), "XCLocalSwiftPackageReference", relativePath=PACKAGE_PATH
    )

    def package_product(target: str, product: str) -> str:
        return project.add(
            uid("packageproduct", target, product), "XCSwiftPackageProductDependency", productName=product
        )

    # ---- Build phases -----------------------------------------------------
    def sources_phase(target: str) -> str:
        build_files = [
            project.add(uid("buildfile", target, str(path)), "PBXBuildFile", fileRef=uid("file", str(path)))
            for path in files[target]
            if path.suffix == ".swift"
        ]
        return project.add(
            uid("sources", target),
            "PBXSourcesBuildPhase",
            buildActionMask=2147483647,
            files=build_files,
            runOnlyForDeploymentPostprocessing=0,
        )

    def resources_phase(target: str) -> str:
        build_files = [
            project.add(uid("buildfile", target, str(path)), "PBXBuildFile", fileRef=uid("file", str(path)))
            for path in files[target]
            if path.suffix in (".xcassets", ".xcprivacy")
        ]
        return project.add(
            uid("resources", target),
            "PBXResourcesBuildPhase",
            buildActionMask=2147483647,
            files=build_files,
            runOnlyForDeploymentPostprocessing=0,
        )

    def frameworks_phase(target: str, product_dependencies: list[str]) -> str:
        build_files = [
            project.add(uid("buildfile", target, "framework", dependency), "PBXBuildFile", productRef=dependency)
            for dependency in product_dependencies
        ]
        return project.add(
            uid("frameworks", target),
            "PBXFrameworksBuildPhase",
            buildActionMask=2147483647,
            files=build_files,
            runOnlyForDeploymentPostprocessing=0,
        )

    def dependency(owner: str, target: str, target_id: str) -> str:
        proxy = project.add(
            uid("proxy", owner, target),
            "PBXContainerItemProxy",
            containerPortal=project_id,
            proxyType=1,
            remoteGlobalIDString=target_id,
            remoteInfo=target,
        )
        return project.add(uid("dependency", owner, target), "PBXTargetDependency", target=target_id, targetProxy=proxy)

    # ---- Build settings ---------------------------------------------------
    common_target = {
        "CODE_SIGN_STYLE": "Automatic",
        "GENERATE_INFOPLIST_FILE": "NO",
        "PRODUCT_NAME": "$(TARGET_NAME)",
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "SWIFT_VERSION": "5.0",
        "TARGETED_DEVICE_FAMILY": "1",
    }

    def app_settings() -> dict:
        return {
            **common_target,
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "CODE_SIGN_ENTITLEMENTS": "ReplyRight/Resources/ReplyRight.entitlements",
            "ENABLE_PREVIEWS": "YES",
            "INFOPLIST_FILE": "ReplyRight/Resources/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
            "PRODUCT_BUNDLE_IDENTIFIER": "$(RR_BUNDLE_ID_PREFIX).app",
        }

    def extension_settings(folder: str, suffix: str) -> dict:
        return {
            **common_target,
            "APPLICATION_EXTENSION_API_ONLY": "YES",
            "CODE_SIGN_ENTITLEMENTS": f"{folder}/{folder}.entitlements",
            "INFOPLIST_FILE": f"{folder}/Info.plist",
            "LD_RUNPATH_SEARCH_PATHS": [
                "$(inherited)",
                "@executable_path/Frameworks",
                "@executable_path/../../Frameworks",
            ],
            "PRODUCT_BUNDLE_IDENTIFIER": f"$(RR_BUNDLE_ID_PREFIX).app.{suffix}",
            "SKIP_INSTALL": "YES",
        }

    def ui_test_settings() -> dict:
        return {
            "CODE_SIGN_STYLE": "Automatic",
            "GENERATE_INFOPLIST_FILE": "YES",
            "PRODUCT_BUNDLE_IDENTIFIER": "$(RR_BUNDLE_ID_PREFIX).app.uitests",
            "PRODUCT_NAME": "$(TARGET_NAME)",
            "SWIFT_VERSION": "5.0",
            "TARGETED_DEVICE_FAMILY": "1",
            "TEST_TARGET_NAME": "ReplyRight",
        }

    # ---- Targets ----------------------------------------------------------
    target_ids = {name: uid("target", name) for name in target_dirs}

    def native_target(name, product_type, phases, dependencies, package_products, settings) -> None:
        project.add(
            target_ids[name],
            "PBXNativeTarget",
            buildConfigurationList=project.configuration_list(f"target-{name}", dict(settings), dict(settings)),
            buildPhases=phases,
            buildRules=[],
            dependencies=dependencies,
            name=name,
            packageProductDependencies=package_products,
            productName=name,
            productReference=product_refs[name],
            productType=product_type,
        )

    # Keyboard extension: ReplyRightCore only, to stay light on memory.
    keyboard_core = package_product("ReplyRightKeyboard", "ReplyRightCore")
    native_target(
        "ReplyRightKeyboard",
        "com.apple.product-type.app-extension",
        [
            sources_phase("ReplyRightKeyboard"),
            frameworks_phase("ReplyRightKeyboard", [keyboard_core]),
            resources_phase("ReplyRightKeyboard"),
        ],
        [],
        [keyboard_core],
        extension_settings("ReplyRightKeyboard", "keyboard"),
    )

    share_products = [package_product("ReplyRightShare", p) for p in ("ReplyRightCore", "ReplyRightUI")]
    native_target(
        "ReplyRightShare",
        "com.apple.product-type.app-extension",
        [
            sources_phase("ReplyRightShare"),
            frameworks_phase("ReplyRightShare", share_products),
            resources_phase("ReplyRightShare"),
        ],
        [],
        share_products,
        extension_settings("ReplyRightShare", "share"),
    )

    app_products = [package_product("ReplyRight", p) for p in ("ReplyRightCore", "ReplyRightUI")]
    embed_files = [
        project.add(
            uid("buildfile", "ReplyRight", "embed", extension),
            "PBXBuildFile",
            fileRef=product_refs[extension],
            settings={"ATTRIBUTES": ["RemoveHeadersOnCopy"]},
        )
        for extension in ("ReplyRightKeyboard", "ReplyRightShare")
    ]
    embed_phase = project.add(
        uid("embed", "ReplyRight"),
        "PBXCopyFilesBuildPhase",
        buildActionMask=2147483647,
        dstPath="",
        dstSubfolderSpec=13,
        files=embed_files,
        name="Embed Foundation Extensions",
        runOnlyForDeploymentPostprocessing=0,
    )
    native_target(
        "ReplyRight",
        "com.apple.product-type.application",
        [
            sources_phase("ReplyRight"),
            frameworks_phase("ReplyRight", app_products),
            resources_phase("ReplyRight"),
            embed_phase,
        ],
        [
            dependency("ReplyRight", "ReplyRightKeyboard", target_ids["ReplyRightKeyboard"]),
            dependency("ReplyRight", "ReplyRightShare", target_ids["ReplyRightShare"]),
        ],
        app_products,
        app_settings(),
    )

    native_target(
        "ReplyRightUITests",
        "com.apple.product-type.bundle.ui-testing",
        [
            sources_phase("ReplyRightUITests"),
            frameworks_phase("ReplyRightUITests", []),
            resources_phase("ReplyRightUITests"),
        ],
        [dependency("ReplyRightUITests", "ReplyRight", target_ids["ReplyRight"])],
        [],
        ui_test_settings(),
    )

    # ---- Project ----------------------------------------------------------
    shared = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_ENUM_CONVERSION": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_INT_CONVERSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "COPY_PHASE_STRIP": "NO",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_64_TO_32_BIT_CONVERSION": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNINITIALIZED_AUTOS": "YES_AGGRESSIVE",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
        "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
        "MTL_FAST_MATH": "YES",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
    }
    debug = {
        **shared,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_DYNAMIC_NO_PIC": "NO",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": ["DEBUG=1", "$(inherited)"],
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG $(inherited)",
        "SWIFT_OPTIMIZATION_LEVEL": "-Onone",
    }
    release = {
        **shared,
        "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "VALIDATE_PRODUCT": "YES",
    }

    project.add(
        project_id,
        "PBXProject",
        attributes={
            "BuildIndependentTargetsInParallel": 1,
            "LastSwiftUpdateCheck": 1600,
            "LastUpgradeCheck": 1600,
            "TargetAttributes": {
                target_ids["ReplyRight"]: {"CreatedOnToolsVersion": "16.0"},
                target_ids["ReplyRightKeyboard"]: {"CreatedOnToolsVersion": "16.0"},
                target_ids["ReplyRightShare"]: {"CreatedOnToolsVersion": "16.0"},
                target_ids["ReplyRightUITests"]: {
                    "CreatedOnToolsVersion": "16.0",
                    "TestTargetID": target_ids["ReplyRight"],
                },
            },
        },
        buildConfigurationList=project.configuration_list("project", debug, release, base_configs),
        compatibilityVersion="Xcode 15.0",
        developmentRegion="en",
        hasScannedForEncodings=0,
        knownRegions=["en", "Base"],
        mainGroup=main_group,
        packageReferences=[local_package],
        productRefGroup=products_group,
        projectDirPath="",
        projectRoot="",
        targets=[
            target_ids["ReplyRight"],
            target_ids["ReplyRightKeyboard"],
            target_ids["ReplyRightShare"],
            target_ids["ReplyRightUITests"],
        ],
    )

    # ---- Serialise --------------------------------------------------------
    by_isa: dict[str, list[tuple[str, dict]]] = {}
    for identifier, fields in project.objects.items():
        by_isa.setdefault(fields["isa"], []).append((identifier, fields))

    lines = ["// !$*UTF8*$!", "{", "\tarchiveVersion = 1;", "\tclasses = {", "\t};", "\tobjectVersion = 60;", "\tobjects = {"]
    for isa in sorted(by_isa):
        lines.append("")
        lines.append(f"/* Begin {isa} section */")
        for identifier, fields in sorted(by_isa[isa], key=lambda item: item[0]):
            lines.append(f"\t\t{identifier} = {render(fields, 2)};")
        lines.append(f"/* End {isa} section */")
    lines += ["\t};", f"\trootObject = {project_id};", "}", ""]
    return "\n".join(lines)


SCHEME = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{app}"
               BuildableName = "ReplyRight.app"
               BlueprintName = "ReplyRight"
               ReferencedContainer = "container:ReplyRight.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "ReplyRightCoreTests"
               BuildableName = "ReplyRightCoreTests"
               BlueprintName = "ReplyRightCoreTests"
               ReferencedContainer = "container:Packages/ReplyRightKit">
            </BuildableReference>
         </TestableReference>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uitests}"
               BuildableName = "ReplyRightUITests.xctest"
               BlueprintName = "ReplyRightUITests"
               ReferencedContainer = "container:ReplyRight.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app}"
            BuildableName = "ReplyRight.app"
            BlueprintName = "ReplyRight"
            ReferencedContainer = "container:ReplyRight.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
      <StoreKitConfigurationFileReference
         identifier = "../../ReplyRight.storekit">
      </StoreKitConfigurationFileReference>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{app}"
            BuildableName = "ReplyRight.app"
            BlueprintName = "ReplyRight"
            ReferencedContainer = "container:ReplyRight.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

WORKSPACE = """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""


def main() -> None:
    (PROJECT / "project.xcworkspace").mkdir(parents=True, exist_ok=True)
    (PROJECT / "xcshareddata" / "xcschemes").mkdir(parents=True, exist_ok=True)

    (PROJECT / "project.pbxproj").write_text(build())
    (PROJECT / "project.xcworkspace" / "contents.xcworkspacedata").write_text(WORKSPACE)
    scheme = SCHEME.replace("{app}", uid("target", "ReplyRight")).replace(
        "{uitests}", uid("target", "ReplyRightUITests")
    )
    (PROJECT / "xcshareddata" / "xcschemes" / "ReplyRight.xcscheme").write_text(scheme)
    print(f"Wrote {PROJECT.relative_to(ROOT.parent)}")


if __name__ == "__main__":
    main()
