#!/usr/bin/env python3

# The neopkg utility creates packages for m3neos.
#
# The script has partial knowledge of package dependencies, as
# encoded in the file `etc/neoinfo.txt` which topologically sorts
# all known packages in dependency order.
#
# Unfortunately it does not have full knowledge of package
# dependencies, so it is not able to ensure that all required
# dependencies for a package are either up-to-date or installed. The
# commands therefore perform cleanup before generating fresh archives.
#
# Features:
#
# * New system installs
#   On a new system without a pre-existing MM3 compiler, this script
#   can build and install a bootstrap compiler (from C source) then build a
#   new compiler binary archive which may be unpacked for installation.
#
# * Boostrap creation
#   For developers this utility can produce sources for a bootstrap
#   compiler by compiling the Modula-3 compiler sources to C.
#
# * Source distro creation
#   The script can produce a source distribution tarball for new system
#   installes which includles the bootstrap compiler files.
#
# * Package installation
#   Once m3neos has been installed on site, this utility can augment the
#   installation with additional packages from the original CM3 source
#   distribution.
#


import os
import platform
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

from pathlib import Path


# The canonical package set defined in neoinfo.txt.
ALL = "all"

# Packages without UI dependencies.
HEADLESS = "headless"

# Operating system classifications.
POSIX = "POSIX"
WIN32 = "WIN32"


# Setup logging to `package.log`

class Tee:
    "Utility for capturing all output to logfile"

    def __init__(self, left, right):
        self._left = left
        self._right = right

    def write(self, data):
        self._left.write(data)
        self._right.write(data)

    def flush(self):
        self._left.flush()
        self._right.flush()

# Capture all output to logfile in the current directory.
logfile = Path(sys.argv[0]).with_suffix(".log").name

# Replace any existing logfile.
sys.stdout = Tee(sys.stdout, open(logfile, "w"))
sys.stderr = sys.stdout

# Start by logging the command-line.
print(*sys.argv)


def show_usage():
    print(f"""usage: {sys.argv[0]} COMMAND {{GENERAL_OPTION}} [COMPILER_OPTIONS]

*** Getting Started ***

To install Modula-3 neos, use the 'bin' command:
  * {sys.argv[0]} bin
  * unpack the generated archive to a location of your choice
  * include the bin directory in your PATH
  * m3neos -?


*** Reference ***

For those who want to modify m3neos, the full set of commands are

  * bin  :: create an archive for on-site installation
            Given the m3neos distribution source-code, this command
            uses a C-compiler to bootstrap a Modula-3 compiler, then
            uses that to compile the Modula-3 source of m3neos into binary
            and ascii files needed for m3neos.

  * boot :: create an m3neos bootstrap archive of C source code
            Using the on-site m3neos compiler and source tree, this
            command compiles the Modula-3 m3neos source code into C,
            which can be compiled to create an m3neos compiler without a
            Modula-3 compiler.

  * src  :: create a distribution source-code archive
            Package a bootstrap compiler and the m3neos Modula-3 source
            code into an archive, to be installed by the bin command.

  * add  :: add a CM3 package to the site
            use m3neos to install on this site any of the plethora of Modula-3
            libraries from the original Critical Mass github repository; the
            bin command above only includes the m3neos compiler and co-requisites


*** Options ***

The 'bin' command uses cmake to bootstrap the m3neos compiler. Defaults
are taken care for installation, but you can set your own:

    CMAKE_OPTIONS = -DCMAKE_<name> | -DCMAKE_<name>=<value>


The following options apply to all commands:

    GENERAL_OPTION = -k | --keep-going | -l | --list-only | -n | --no-action

      * -k | --keep-going :: ignore errors and continue with commands
      * -l | --list-only  :: list packages that would be affected
      * -n | --no-action  :: print commands to execute, but make no changes


Compiler options are passed through to m3neos

    COMPILER_OPTIONS = {{COMPILER_FLAG}} {{COMPILER_DEFINE}} [TARGET_OPTION]

    COMPILER_FLAG = -boot | -commands | -debug | -keep | -override | -silent | -times | -trace | -verbose | -why

      * -commands :: list system commands as they are performed
      * -debug :: dump internal debugging information
      * -keep :: preserve intermediate and temporary files
      * -override :: include the "m3overrides" file
      * -silent :: produce no diagnostic output
      * -times :: produce a dump of elapsed times
      * -trace :: trace quake code execution
      * -verbose :: list internal steps as they are performed
      * -why :: explain why code is being recompiled

    COMPILER_DEFINE = -D<name> | -D<name>=<value>
        Defines are passed verbatim to m3neos.

    TARGET_OPTION = --target <name>
        Select the compile target, for example x86_64. 
        Alternative option is wasm32

""")


class Error(Exception):
    pass


class FatalError(Error):
    def __init__(self, message):
        self.message = message


class UsageError(Error):
    def __init__(self, message):
        self.message = message


class Platform:
    """Describes compilation host or target

    Given a MM3 platform name, this class provides knowledge of what
    backends and features MM3 supports on that platform.
    """

    @staticmethod
    def normalize_platform(name):
        "Error if name does not match a known platform"
        for target in Platform._all_platforms():
            if name.upper() == target.upper():
                return target
        raise UsageError(f"{name} is not a recognized target")

    @staticmethod
    def _all_platforms():
        "Streamlined set of platforms"
        m3neos_platforms = ["x86_64", "wasm32"]
        return m3neos_platforms

    def __init__(self, name = None):
        if not name:
            # Some attempts to disambiguate _MINGW and _NT.
            if os.environ.get("MINGW_CHOST", "").startswith("x86_64"): name = "AMD64_MINGW"
            elif os.environ.get("MSYSTEM") == "MINGW64":               name = "AMD64_MINGW"
            elif os.environ.get("MINGW_CHOST", "").startswith("i686"): name = "I386_MINGW"
            elif os.environ.get("MSYSTEM") == "MINGW32":               name = "I386_MINGW"
        if not name:
            name = self._map_arch(platform.machine())
        self._name = Platform.normalize_platform(name)

    def has_gcc_backend(self):
        "Supported by GCC backend"
        name = self.name()

        # These backends require Visual Studio.
        if name == "NT386" or name.endswith("_NT"):
            return False

        # Our GCC is too old for ARM support.
        if re.match(r"ARM|SOL", name):
            return False

        # Many platforms only work on the C backend, or at least
        # there are no protesting users.
        if re.search(r"ALPHA|CYGWIN|MINGW|OSF|RISCV|SOLARIS|HPUX|IA64|HAIKU", name):
            return False

        return True


    def has_integrated_backend(self):
        "The integrated backend supports only 32-bit Windows"
        return self.name() in ["NT386", "I386_NT"]

    def has_serial(self):
        return self.is_win32()

    def is_mingw(self):
        return self.name().endswith("_MINGW")

    def is_nt(self):
        return self.name() == "NT386" or self.name().endswith("_NT")

    def is_posix(self):
        return not self.is_win32()

    def is_win32(self):
        return self.is_mingw() or self.is_nt()

    def name(self):
        "As recognized by m3neos"
        return self._name

    def os(self):
        "As recognized by m3neos"
        return WIN32 if self.is_win32() else POSIX

    def _map_arch(self, arch):
        "Map Python's architecture name to MM3's architecture name"
        if arch == "x86_64": arch = "x86_64"
        if arch == "x86": arch = "i386"
        return arch

    def _map_os(self, os):
        if os == "win32": os = "nt"
        if os.startswith("openbsd"): os = "openbsd" # e.g. openbsd7
        return os


class M3N:
    """MM3 build environment

    This class is primarily responsible for running the MM3 compiler.
    It locates the compiler and the MM3 source and install
    directories.  It tracks requested compiler options (flags and
    defines) and the current compilation target.
    """

    def __init__(self, script, backend="c", defines=None, flags=None, target=None, install_dir=None):
        # The script is used to locate the source directory.
        self._script  = script

        # Defines the backend to use when compiling packages.
        self._backend = backend

        # Various MM3 compiler options requested by the user.
        self._defines = defines or []
        self._flags   = flags or []
        self._install_dir = install_dir

        # Compilation host and target platforms.
        self._host    = None
        self._target  = None
        if target:
            self._target = target if isinstance(target, Platform) else Platform(target)

        # Misc. options to direct the overall behavior of the
        # concierge script.
        self._keep_going = False
        self._list_only  = False
        self._no_action  = False

    def backend(self):
        "The compiler backend to use when building packages"

        # Don't try to use GCC when not available.
        if self._backend == "gcc" and not self.target().has_gcc_backend():
            self._backend = "c"

        # Don't try to use the integrated backend when not available.
        if self._backend == "integrated" and not self.target().has_integrated_backend():
            self._backend = "c"

        return self._backend

    def build(self, *paths):
        "Relative to root of current build directory"
        return self.source(*paths) / self.build_dir()

    def build_dir(self):
        "Basename of build directory"
        return self.config()

    def config(self):
        "Used as an alias of target name"
        return self.target().name()

    def defines(self):
        "Any '-D' command-line arguments intended for m3neos"
        return self._defines

    def env(self):
        "Execution environment for m3neos child processes"

        # TODO it is not clear if some or all of these are redundant,
        # given the defines passed to m3neos on the command-line (in
        # `PackageAction.run`).  These may simply have been an
        # out-of-band communication mechanism for the legacy scripts.
        return dict(
            os.environ
        )

    def exe(self):
        "Full path to m3neos executable"

        def fail():
            raise FatalError(basename + " not found in PATH")

        # With no overrides, we search PATH.
        basename = "m3neos"
        candidate = self._find_exe(basename)
        if candidate is None:
            fail()

        return candidate

    def _find_exe(self, basename):
        "Look for an executable in PATH"

        # Search PATH.
        for dir in os.get_exec_path():
            # Posix
            candidate = Path(dir, basename)
            if candidate.is_file() and os.access(candidate, os.X_OK):
                return candidate.resolve()
            # Windows
            candidate = candidate.with_suffix(".exe")
            if candidate.is_file():
                return candidate.resolve()

        # Not found.
        return None

    def flags(self):
        "Command-line arguments intended for m3neos"
        return self._flags

    def host(self):
        "Compilation host, only used as default for target"
        if not self._host:
            self._host = self._sniff_host()
        return self._host

    def _sniff_host(self):
        "Guess the host platform"
        try:
            # Ask m3neos.
            output = subprocess.check_output([str(self.exe()), "-version"], errors="ignore")
            for line in output.splitlines():
                host = line.find("host: ")
                if host >= 0:
                    return Platform(line[host + 6:].rstrip())
        except:
            pass

        # If there's a problem, we'll make our best guess.
        return Platform()

    def install(self, *paths):
        "Relative to root of current installation directory"

        if not self._install_dir:
            self._install_dir = Path(self.source(), self.config())
            print("Default installation: ", self._install_dir)

        return self._install_dir.joinpath(*paths)

    def keep_going(self):
        "Continue running the concierge script in event of errors"
        return self._keep_going

    def list_only(self):
        "List packages selected by current command-line"
        return self._list_only

    def no_action(self):
        "Perform a dry-run, do not make any changes to the system"
        return self._no_action

    def script(self):
        "The script is used to locate the source directory"
        return Path(self._script).resolve()

    def set_options(self, namespace):
        "Inform MM3 of options detected in argument parsing"
        for attr in ["_keep_going", "_list_only", "_no_action"]:
            if hasattr(namespace, attr):
                setattr(self, attr, getattr(namespace, attr))

    def source(self, *paths):
        "Relative to root of current source directory"
        script_path = self.script()
        script_dir  = script_path.parent
        source_dir  = script_dir.parent
        return source_dir.joinpath(*paths)

    def target(self):
        "Compilation target, passed to MM3"
        if not self._target:
            self._target = self._sniff_target()
        return self._target

    def _sniff_target(self):
        "Guess the target platform"
        try:
            # Ask m3neos.
            output = subprocess.check_output([str(self.exe()), "-version"], errors="ignore")
            for line in output.splitlines():
                target = line.find("target: ")
                if target >= 0:
                    return Platform(line[target + 8:].rstrip())
        except:
            pass

        # If there's a problem, assume we're compiling for the host machine.
        return self.host()

    def use_c_backend(self):
        return self.backend() == "c"


class WithM3N:
    "Provides access to m3neos build context"

    def __init__(self, m3neos):
        self._m3neos = m3neos

    def __getattr__(self, method_name):
        "Delegate some requests to MM3"
        forwards = [
            "build",
            "build_dir",
            "config",
            "defines",
            "env",
            "exe",
            "flags",
            "host",
            "install",
            "keep_going",
            "list_only",
            "no_action",
            "source",
            "target",
            "use_c_backend"
        ]
        if method_name not in forwards:
            raise AttributeError
        return getattr(self.m3neos(), method_name)

    def m3neos(self):
        return self._m3neos

    def rmdir(self, dir):
        "Recursively remove a directory"
        if dir.is_dir():
            print("rm", "-Rf", dir)
            if not self.no_action():
                shutil.rmtree(dir)


class PackageDatabase(WithM3N):
    """Knows what packages are available and their dependency order

    Whereas `M3N` knows *how* to run the compiler, the package
    database knows *where* and *when* (in what order) to run the
    compiler to build a set of requested packages.
    """

    def __init__(self, m3neos):
        super().__init__(m3neos)

        # There is an order dependency here, sets must be loaded
        # before the index.
        self._load_package_sets()
        self._load_package_index()

    def all_packages(self):
        "Canonical list of packages, in dependency order, as defined in neoinfo.txt"

        # This is a superset of the packages available on the system.
        return self._package_sets[ALL]

    def get_package_paths(self, names):
        """Locations of all requested packages, where `names` is a mixed list
        of individual packages and package sets"""

        # These packages will be present on the system.
        return [self.get_package_path(pkg) for pkg in self.get_packages(names)]

    def get_package_path(self, name):
        "Location of package relative to root of source tree"
        try:
            return self._package_index[name]
        except:
            raise FatalError(f"package {name} requested but not found")

    def get_packages(self, names):
        """List of requested packages, in dependency order

        Here `names` is a mixed list of packages and package sets, and
        may use the add/remove syntax (`+` or `-`) to make specific
        requests.

        The returned packages may be a subset of those requested,
        limited by what is available on the system.  For example, a
        request to build the GCC backend (`m3cc`) may come up empty
        when GCC is not included in the distribution.
        """

        # First determine what packages are requested, then later we
        # will work-out the bulid order.
        requested = set()

        # Incorporate each listed package or set into requested.
        for name in names:
            remove = name.startswith("-")
            if name.startswith("+") or name.startswith("-"):
                name = name[1:]

            if name in self._package_sets:
                # name identifies a package set
                if remove:
                    for package in self._package_sets[name]:
                        if package in requested:
                            requested.remove(package)
                else:
                    for package in self._package_sets[name]:
                        requested.add(package)
            elif name in self._package_index:
                # name identifies an individual package
                package = name
                if remove:
                    if package in requested:
                        requested.remove(package)
                else:
                    requested.add(package)

        # Determine the canonical order for all requested packages.
        packages = []
        for package in self.all_packages():
            if package in requested and package in self._package_index:
                packages.append(package)

        # Finally, omit anything not available to the current target.
        return self._filter_packages(packages)

    def is_package(self, name):
        "Name identifies a package or package set"
        if name.startswith("+") or name.startswith("-"):
            name = name[1:]
        return self._package_sets.get(name) or self._package_index.get(name)

    def _filter_packages(self, packages):
        "Exclude from packages anything that can't work in the target environment"
        return [pkg for pkg in packages if self._include_package(pkg)]

    def _include_package(self, name):
        "Do we try to build this package?"

        if name == "X11R4":  return self.target().is_posix()
        if name == "m3cc":   return False
        if name == "m3gdb":  return False
        if name == "serial": return self.target().has_serial() or  os.environ.get("HAVE_SERIAL")
        if name == "tapi":   return self.target().is_win32()
        if name == "tcl":    return os.environ.get("HAVE_TCL")
        return True

    def _load_package_index(self):
        """Scan the source directory for available packages

        Importantly, the package index reflects what packages actually
        exist and can be installed.  The packages listed in
        neoinfo.txt are a superset of what is actually available.
        """

        # Find all the fully-qualified package paths.
        package_paths = []

        root = self.source()
        for dir, children, files in os.walk(root):
            dir = Path(dir)

            # src may be a package directory
            if dir.name == "src" and "m3makefile" in files:
                package_dir  = dir.parent
                package_path = package_dir.relative_to(root).as_posix()
                package_paths.append(package_path)

                # We can prune the search here.
                children.clear()

            # We can also prune specific, named directories.
            if dir.name.startswith(".") or dir.name.startswith("_"):
                children.clear()

            if str(dir.as_posix()).endswith("examples/web"):
                children.clear()

        # Look for package names in the canonical list.
        self._package_index = dict()

        package_list = self.all_packages()
        for package_path in package_paths:
            # Find the canonical name of the package.  The canonical
            # name is some sub-path of the relative directory that
            # uniquely identifies the package in `neoinfo.txt`.
            package_name = str(package_path)
            while package_name not in package_list and package_name.find("/") >= 0:
                # Keep stripping off leading directories until we find
                # a match.
                package_name = package_name[package_name.find("/")+1:]

            # Index the package by its canonical name, if found.
            if package_name in package_list:
                self._package_index[package_name] = package_path

    def _load_package_sets(self):
        """Read package definitions from neoinfo.txt

        neoinfo.txt defines the canonical names of all known packages
        and their relative dependency order.  This is separate from
        the information about what packages are actually available.
        """

        self._package_sets = dict()
        with open(self.source("etc/neoinfo.txt"), "r") as pkginfo:
            for line in pkginfo:
                line = line.rstrip()
                if not line:
                    continue
                package, *sets = line.split()
                sets.insert(0, ALL)
                for set in sets:
                    self._package_sets.setdefault(set, []).append(package)


class PackageAction(WithM3N):
    "Runs m3neos on a list of packages identified by relative paths"

    def __init__(self, m3neos):
        super().__init__(m3neos)
        self._success = False

    def execute(self, package_paths):
        "Runs m3neos for each listed package"
        self._success = True
        for package_path in package_paths:
            try:
                self.execute_path(package_path)
            except:
                self._success = False
                if not self.keep_going():
                    raise

    def run(self, package_path, args):
        "Execute a m3neos child process"
        cwd  = self.source(package_path)
        args = [str(self.exe())] + args + self.defines() + self.flags()
        print("cd", cwd)
        print(*args)

        if self.no_action():
            return

        proc = subprocess.run(
            args,
            cwd=cwd,
            env=self.env(),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            errors="ignore"
        )
        sys.stdout.write(proc.stdout)
        proc.check_returncode()

    def success(self):
        "The last action was fully successful, with no failures"
        return self._success

    def defines(self):
        "List of '-D' arguments to pass to m3neos"

        # TODO see comment in `M3N.env`
        defines = [
            f"-DBUILD_DIR={self.build_dir()}",
            f"-DROOT={self.source()}",
            f"-DTARGET={self.config()}"
        ]

        # Where the gcc or integrated backends are available, they are
        # the default for their respective platforms and do not need
        # to be specified.
        if self.use_c_backend():
            defines.append(f"-DM3_BACKEND=C")

        # Include any defines given on the command-line.
        return defines + self.m3neos().defines()


class CleanAction(PackageAction):
    "Clean actions need to reverse the package order, and can safely ignore errors"

    def execute(self, package_paths):
        # Clean in reverse dependency order to avoid warnings.
        self._success = True
        for package_path in reversed(package_paths):
            try:
                self.execute_path(package_path)
            except:
                self._success = False
                if not self.keep_going():
                    raise

    def keep_going(self):
        "Ignore errors when cleaning"
        return True


class BuildGlobal(PackageAction):
    "Build package without overrides"

    def execute_path(self, package_path):
        self.run(package_path, ["-build"])


class RealClean(CleanAction):
    "Remove target directory of package"

    def execute_path(self, package_path):
        self.rmdir(self.build(package_path))


class Ship(PackageAction):
    "Install package"

    def execute_path(self, package_path):
        self.run(package_path, ["-ship"])


class BuildShip(PackageAction):
    "Build package *without* overrides and install it"

    def __init__(self, m3neos):
        super(BuildShip, self).__init__(m3neos)
        self._buildglobal = BuildGlobal(m3neos)
        self._ship = Ship(m3neos)

    def execute_path(self, package_path):
        # These have to be done in lockstep.  Because of various
        # unclear dependencies, building everything before shipping
        # anything yields a broken system.
        self._buildglobal.execute_path(package_path)
        self._ship.execute_path(package_path)

    def keep_going(self):
        "If the build fails, we don't ship"
        return False


class WithPackageDb(WithM3N):
    "Provides access to package database"

    def __init__(self, m3neos, package_db):
        super().__init__(m3neos)
        self._package_db = package_db

    def get_package_paths(self, names):
        "Locations of all requested packages"
        return self.package_db().get_package_paths(names)

    def is_package(self, name):
        "Name identifies a package or package set"
        return self.package_db().is_package(name)

    def package_db(self):
        return self._package_db


# Maps action names to command objects, but also provides a canonical
# list of available package actions.
PACKAGE_ACTIONS = dict(

    # Build without local overrides.  This is necessary for anything
    # we want to install.
    buildglobal=BuildGlobal,

    # Build without overrides, then install.
    buildship=BuildShip,

    # Instead of running clean, just nuke all the build directories.
    realclean=RealClean,
)


class WithPackageActions(WithPackageDb):
    "Conveniences for executing package actions"

    def __init__(self, m3neos, package_db):
        super().__init__(m3neos, package_db)

    # Note that this won't generate a "build" method, because that is
    # already defined in WithM3N with an entirely different meanning.
    # It is better to be specific with "buildglobal" or "buildlocal"
    # if that is what is needed.
    def __getattr__(self, method_name):
        # Defer first to the methods defined in `WithM3N`.
        try:
            return super().__getattr__(method_name)
        except AttributeError:
            pass

        # Only if that fails, look for a named package action.
        try:
            constructor = PACKAGE_ACTIONS[method_name]
            action = constructor(self.m3neos())
            def executor(packages):
                paths = self.get_package_paths(packages)
                print(method_name, *paths)
                action.execute(paths)
            return executor
        except KeyError:
            raise AttributeError


class PackageCommand(WithPackageActions):
    "A top-level command made to the packager"

    def __init__(self, m3neos, package_db):
        super().__init__(m3neos, package_db)
        self._tag = None


    @classmethod
    def parse_args(cls, args, namespace):
        "Interpret arguments common to all commands"
        cls._parse_compiler_options(args, namespace)
        cls._parse_options(args, namespace)

    @classmethod
    def parse_packages(cls, args, namespace):
        "After parsing all arguments, assume anything left is a package specification"
        packages = args[:]
        args.clear()
        setattr(namespace, "_packages", packages)

    @classmethod
    def _parse_options(cls, args, namespace):
        "Global options that direct concierge behavior"

        keep_going = False
        list_only  = False
        no_action  = False

        for option in ["-k", "--keep-going"]:
            while option in args:
                args.remove(option)
                keep_going = True

        for option in ["-l", "--list-only"]:
            while option in args:
                args.remove(option)
                list_only = True

        for option in ["-n", "--no-action"]:
            while option in args:
                args.remove(option)
                no_action = True

        setattr(namespace, "_keep_going", keep_going)
        setattr(namespace, "_list_only",  list_only)
        setattr(namespace, "_no_action",  no_action)

    @classmethod
    def _parse_compiler_options(cls, args, namespace):
        "Any arguments that define how we call-out to the compiler"
        cls._parse_backend(args, namespace)
        cls._parse_defines(args, namespace)
        cls._parse_flags(args, namespace)
        cls._parse_target(args, namespace)

    @classmethod
    def _parse_backend(cls, args, namespace):
        "Look for any command-line argument specifying a backend"

        # Default.
        backend = "c"

        tail = args[:]
        args.clear()
        while tail:
            head = tail.pop(0)
            if head == "--backend":
                if not tail:
                    raise UsageError("missing backend selection")
                backend = tail.pop(0)
            elif head.startswith("--backend="):
                backend = head[10:]
            elif head in ["-c", "-gcc", "-integrated"]:
                backend = head[1:]
            else:
                args.append(head)

        if backend not in ["", "c", "gcc", "integrated", "StAloneLlvmObj", "StAloneLlvmAsm", "9", "10"]:
            raise UsageError(f"{backend} is not a recognized backend")

        setattr(namespace, "_backend", backend)

    @classmethod
    def _parse_defines(cls, args, namespace):
        "Look for defines that need to be passed-through to m3neos"
        defines = [arg for arg in args if arg.startswith("-D") and not arg.startswith("-DCMAKE_")]
        args[:] = [arg for arg in args if arg not in defines]
        setattr(namespace, "_defines", defines)

    @classmethod
    def _parse_flags(cls, args, namespace):
        "Look for flags that need to be passed-through to m3neos"
        m3neosflags = [
            "-boot",
            "-commands",   # list system commands as they are performed
            "-debug",      # dump internal debugging information
            "-keep",       # preserve intermediate and temporary files
            "-override",   # include the "m3overrides" file
            "-silent",     # produce no diagnostic output
            "-times",      # produce a dump of elapsed times
            "-trace",      # trace quake code execution
            "-verbose",    # list internal steps as they are performed
            "-why"         # explain why code is being recompiled
        ]
        flags   = [arg for arg in args if arg in m3neosflags]
        args[:] = [arg for arg in args if arg not in flags]
        setattr(namespace, "_flags", flags)

    @classmethod
    def _parse_target(cls, args, namespace):
        target = None

        tail = args[:]
        args.clear()
        while tail:
            head = tail.pop(0)
            if head == "--target":
                if not tail:
                    raise UsageError("missing target selection")
                target = tail.pop(0)
            elif head.startswith("--target="):
                target = head[9:]
            else:
                args.append(head)

        if target:
            target = Platform.normalize_platform(target)

        setattr(namespace, "_target", target)

    def set_options(self, namespace):
        "Inform command of options detected in argument parsing"
        for attr in ["_actions", "_cmake_args", "_packages", "_prefix"]:
            if hasattr(namespace, attr):
                setattr(self, attr, getattr(namespace, attr))

    def actions(self):
        "List of package actions given on command-line"
        return self._actions

    def packages(self):
        "List of packages requested on the command-line"
        return [pkg for pkg in self._packages if self.is_package(pkg)]

    def version(self):
        return self.tag()

    def tag(self):
        "Get the version from the current tag"
        if self._tag is None:
            try:
                self._tag = subprocess.check_output(["git", "describe", "--abbrev=0"], errors="ignore").rstrip()
            except:
                # Parse the release information
                rel_path = self.source("etc") / "m3neos.release"
                if rel_path.is_file():
                    pattern = re.compile('MM3VERSION[ \t]*=[ \t]*"(.*)"')
                    with open(rel_path, 'r') as rel_file:
                        for line in rel_file:
                            result = pattern.search(line)
                            if result != None:
                                self._tag = result.group(1)
                        rel_file.close()

        # not found
        if self._tag is None:
            self._tag = "nil.tag"

        return self._tag

    def cp(self, src, dst):
        "Copy a file"
        if src.is_file():
            print("cp", "-P", src, dst)
            if not self.no_action():
                shutil.copy(src, dst)

    def rm(self, file):
        "Remove a file"
        if file.is_file():
            print("rm", "-f", file)
            if not self.no_action():
                file.unlink()


    def mkdir(self, dir):
        "Create a directory"
        print("mkdir", "-p", dir)
        if not self.no_action():
            dir.mkdir(parents=True, exist_ok=True)

    def rmdir(self, dir):
        "Recursively remove a directory"
        if dir.is_dir():
            print("rm", "-Rf", dir)
            if not self.no_action():
                shutil.rmtree(dir)


    def zip(self, zipfile, args, cwd=None, noclean = False):
        if not noclean:
            self.rm(Path(zipfile))

        command = ["7z", "a", zipfile] + args
        if not cwd:
            cwd = os.getcwd()

        print(*command)
        if not self.no_action():
            proc = subprocess.run(command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, errors="ignore")
            proc.check_returncode()
            sys.stdout.write(proc.stdout)

    def tar(self, tarfile, args):
        self.rm(Path(tarfile))
        command = ["tar", "acf", tarfile, "--warning=no-file-changed"] + args

        print(*command)
        if not self.no_action():
            proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, errors="ignore")
            sys.stdout.write(proc.stdout)


class CompCommand(PackageCommand):
    "Compile compiler and core system"

    def execute(self):
        base_packages = ["+front", "+m3bundle", "-m3cc"]

        # Guarantee a basic config if we're on a clean system.
        if not self.install("etc/m3neos.cfg").is_file():
            self._install_config()

        # Then ensure we don't use an outdated GCC.
        self._clean()

        # Build the compiler using the installed version of the system.
        self._run_pass(base_packages)

        # Use the new compiler to build the core system.
        self._install_config()
        self._run_pass(base_packages)

    def _clean(self):
        "Delete lingering mm3cg so we can't accidentally use an old version"
        for exe in ["mm3cg", "gcc/m3cgc1"]:
            file = self.build("cmd/m3cc") / exe
            self.rm(file)
            self.rm(file.with_suffix(".exe"))

    def _run_pass(self, packages):
        "Perform one build/iteration within the system upgrade"

        # Build the compiler.
        self.realclean(packages)
        self.buildship(packages)

        self._ship_front()


    def _ship_front(self):
        "Ship the comiler 'frontent', i.e., m3neos"
        self._copy_compiler(self.build("cmd/m3neos"), self.install("bin"))

    def _copy_compiler(self, src, dst):
        "Copy compiler executables to their installed locations"

        executables = ["m3neos", "mm3cg", "mips-tfile", "mklib"]

        # Ensure destination directory exists.
        self.mkdir(dst)

        # Copy executables.
        for exe in executables:
            item = src / exe
            if item.is_file():
                # Posix
                self.cp(item, dst)
            else:
                # Windows
                item = item.with_suffix(".exe")
                self.cp(item, dst)
                # Copy debug info.
                item = item.with_suffix(".pdb")
                self.cp(item, dst)

    def _install_config(self):
        "Copy config for distribution"

        src = self.source("etc")
        dst = self.install("etc")

        # Delete the old config files.
        self.rmdir(dst)

        # Ensure destination directory exists.
        self.mkdir(dst)

        # Copy all files from src to dst.
        for config in src.iterdir():
            self.cp(config, dst)

        # Write new m3neos.cfg
        if self.no_action():
            return

        backend = ''
        if self.use_c_backend():
            backend = 'M3_BACKEND = "C"\n'

        cross_compile = ''
        if self.config() == "I386_LINUX":
            cross_compile = 'SYSTEM_CC = SYSTEM_CC & " -I/usr/i686-linux-gnu/include"\n'

        self.install("etc/m3neos.cfg").write_text(
            f"""if not defined("SL") SL = "/" end
if not defined("M3_BACKEND") M3_BACKEND = "C" end
if not defined("TARGET") TARGET = "x86_64" end
INSTALL_ROOT = (path() & SL & "..")
include(path() & SL & ".." & SL & "etc" & SL & TARGET)
{cross_compile}"""
        )


class BinCommand(PackageCommand):
    "Bootstrap followed by full upgrade"

    @classmethod
    def parse_args(cls, args, namespace):
        super().parse_args(args, namespace)
        cls._parse_cmake_args(args, namespace)
        cls._parse_prefix(args, namespace)
        super().parse_packages(args, namespace)

    @classmethod
    def _parse_cmake_args(cls, args, namespace):
        "Look for arguments that should be passed directly to cmake"

        cmake_args = [arg for arg in args if arg.startswith("-DCMAKE_")]

        tail = [arg for arg in args if arg not in cmake_args]
        args.clear()
        while tail:
            head = tail.pop(0)
            if head == "-G":
                cmake_args.append(head)
                cmake_args.append(tail.pop(0))
            else:
                args.append(head)

        setattr(namespace, "_cmake_args", cmake_args)

    @classmethod
    def _parse_prefix(cls, args, namespace):
        "Specify the desired install location with --prefix"
        prefix = None

        tail = args[:]
        args.clear()
        while tail:
            head = tail.pop(0)
            if head == "--prefix":
                if not tail:
                    raise UsageError("missing install prefix")
                prefix = tail.pop(0)
            elif head.startswith("--prefix="):
                prefix = head[9:]
            else:
                args.append(head)

        setattr(namespace, "_prefix", prefix)

    def __init__(self, m3neos, package_db):
        super().__init__(m3neos, package_db)

        # We'll hand-off to `rebuild` after performing the
        # bootstrap.
        self._rebuild = CompCommand(m3neos, package_db)

    def set_options(self, namespace):
        super().set_options(namespace)
        self._rebuild.set_options(namespace)

    def execute(self):
        "Build the bootstrap compiler, then perform a system upgrade"

        self.bootstrap()

        # Ensure new install is in PATH.
        path = os.environ["PATH"]
        if self.target().is_nt():
            path=f"{str(self.prefix())}/bin;{path}"
        else:
            path=f"{str(self.prefix())}/bin:{path}"

        os.environ["PATH"] = path
        print("PATH=", os.environ["PATH"])

        self.stage_rebuild()


        # Generate tarball.
        pkg_nm = f"m3neos-bin-{self.version()}"
        parent = str(self.source())
        source = self.config()

        if self.target().is_win32():
            self.zip(f"{pkg_nm}.7z", [f"-xr@./.gitignore", f"-xr@./etc/7z.exclude", f"{source}"], cwd=parent)
        else:
            command = [
                "--directory", parent,
                "--exclude=*.7z",
                "--exclude=*.tar.xz",
                f"--transform=s!^{source}!{pkg_nm}!",
                "--exclude-vcs",          # Don't include .git
                "--exclude-vcs-ignores",  # Don't include things ignored by git
                source]
            self.tar(f"{pkg_nm}.tar.xz", command)

    def bootstrap(self):
        "Build the bootstrap compiler"

        # Check that bootstrap sources are available.
        bootstrap_dir = self.source("bootstrap")
        if not (bootstrap_dir / "CMakeLists.txt").is_file():
            raise FatalError("missing bootstrap directory")

        # Run an out-of-tree build with cmake.
        build_dir = self.source("build")
        if self._out_of_tree():
            # User has already created a build directory, so use it.
            self._build_with_cmake(bootstrap_dir, build_dir)
        else:
            # Otherwise try building in /tmp.
            with tempfile.TemporaryDirectory() as build_dir:
                self._build_with_cmake(bootstrap_dir, build_dir)

    def _out_of_tree(self):
        "Working directory is not under inside the source tree"
        return self.source() not in Path(os.getcwd()).parents

    def _build_with_cmake(self, bootstrap_dir, build_dir):
        # Configure and generate.
        setup = ["cmake", "-S", str(bootstrap_dir), "-B", build_dir] + self._cmake_args

        # Define install location.
        setup.append(f"-DCMAKE_INSTALL_PREFIX={self.install()}")

        # Special considerations for MINGW.
        if self.config() == "AMD64_MINGW":
            setup.append("-DCMAKE_LIBRARY_PATH=/mingw64/x86_64-w64-mingw32/lib")
        elif self.config() == "I386_MINGW":
            setup.append("-DCMAKE_LIBRARY_PATH=/mingw32/i686-w64-mingw32/lib")

        # Special considerations for NT.
        if self.config() == "AMD64_NT":
            setup = setup + ["-A", "x64"]
        elif self.config() == "I386_NT":
            setup = setup + ["-A", "Win32"]

        self.rmdir(self.prefix())

        # Build and install.
        build   = ["cmake", "--build",   build_dir]
        install = ["cmake", "--install", build_dir]
        if self.target().is_nt():
            build   = build + ["--config", "Debug"]
            install = install + ["--config", "Debug"]

        # Execute cmake steps.
        for command in [setup, build, install]:
            print(*command)
            if not self.no_action():
                proc = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, errors="ignore")
                sys.stdout.write(proc.stdout)
                proc.check_returncode()

    def stage_rebuild(self):
        "Perform a system rebuild"
        self._rebuild.execute()

    def prefix(self):
        "If not otherwise specified, replace the existing compiler"
        if not self._prefix:
            self._prefix = self.install()
        return Path(self._prefix).resolve()


class BootCommand(PackageCommand):
    "Generate sources for a bootstrap compiler"

    @classmethod
    def parse_args(cls, args, namespace):
        super().parse_args(args, namespace)

        # Override compiler configuration.
        setattr(namespace, "_backend", "c")
        setattr(namespace, "_flags", ["-boot", "-keep"])

    def execute(self):
        # Compile m3neos and its dependencies to C.
        packages = ["+front", "-m3cc", "-m3cgcat", "-m3cggen"]
        self.realclean(packages)
        self.buildglobal(packages)

        # Create bootstrap directory.
        bootstrap_dir = self.source("bootstrap")
        self.rmdir(bootstrap_dir)
        self.mkdir(bootstrap_dir)

        # Copy generated C files to bootstrap.
        package_dirs = []
        for package_path in self.get_package_paths(packages):
            cmakelists = Path(package_path) / "CMakeLists.txt"
            if not cmakelists.is_file():
                continue
            package_dir = bootstrap_dir / Path(package_path).name
            self.mkdir(package_dir)
            self.cp(cmakelists, package_dir)
            package_dirs.append(package_dir.name)

            package_sources = []
            if not self.no_action():
                for file in self.build(package_path).iterdir():
                    if file.suffix in [".c", ".cpp", ".h"]:
                        self.cp(file, package_dir)
                        package_sources.append(file.name)

                with open(package_dir / "sources.lst", "w") as sources:
                    sources.write("set(m3neos_SOURCES\n")
                    for filename in sorted(package_sources):
                        sources.write(f"{filename}\n")
                    sources.write(")\n")

        # Generate CMakeLists.txt
        cmake_install_prefix = f"INSTALL.M3-{self.version()}" if self.version() else "INSTALL.M3"
        cmake_header = f"""cmake_minimum_required(VERSION 3.10)
project(m3neos LANGUAGES C CXX)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
   set(CMAKE_INSTALL_PREFIX "{cmake_install_prefix}" CACHE PATH "..." FORCE)
endif()
include(GNUInstallDirs)
include(neostrap.cmake)
"""
        if not self.no_action():
            with open(bootstrap_dir / "CMakeLists.txt", "w") as cmake:
                cmake.write(cmake_header)
                for dir in sorted(package_dirs):
                    cmake.write(f"add_subdirectory({dir})\n")
        self.cp(self.source("etc/neostrap.cmake"), bootstrap_dir)

        # Generate tarballs.
        pkg_nm = f"m3neos-boot-{self.version()}"
        if self.target().is_win32():
            self.zip(f"{pkg_nm}.7z", ["bootstrap"], cwd=str(self.source()))
        else:
            self.tar(f"{pkg_nm}.tar.xz", ["-C", str(self.source()), "bootstrap"])


class SrcCommand(BootCommand):

    def execute(self):
        # Prepare bootstrap.
        super().execute()

        # Clean.
        self.realclean([ALL])

        # Generate tarball.
        pkg_nm = f"m3neos-src-{self.version()}"
        parent   = str(self.source().parent)
        source   = self.source().name

        if self.target().is_win32():
            self.zip(f"{source}/{pkg_nm}.7z", [f"-xr@{source}/.gitignore", f"-xr@{source}/etc/7z.exclude", f"{source}"], cwd=parent)
            self.zip(f"{source}/{pkg_nm}.7z", [f"{source}/bootstrap"], cwd=parent, noclean=True)
        else:
            parent  = str(self.source().parent)
            command = [
                "--directory", parent,
                "--exclude=*.7z",
                "--exclude=*.tar.xz",
                "--exclude=*.log",
                "--exclude=build",
                "--exclude=.fslckout",
                f"--transform=s!^{source}!{pkg_nm}!",
                "--exclude-vcs",          # Don't include .git
                "--exclude-vcs-ignores",  # Don't include things ignored by git
                source]
            self.tar(f"{pkg_nm}.tar.xz", command)


class AddCommand(PackageCommand):
    "Build and Install a package"

    @classmethod
    def parse_args(cls, args, namespace):
        super().parse_args(args, namespace)
        super().parse_packages(args, namespace)

    def __init__(self, m3neos, package_db):
        m3neos._backend = ""
        super().__init__(m3neos, package_db)

    def set_options(self, namespace):
        super().set_options(namespace)

    def execute(self):
        "Build plus Ship"

        pkgs = self.packages()
        pkgs.append("-m3cc")
        self.buildship(pkgs)



class Package:
    "aka, main"

    def __init__(self, args = None):
        # Context defaults.
        self._m3neos        = None
        self._command    = None
        self._package_db = None
        self._script     = None

        # Bootstrap defaults.
        self._cmake_args = []
        self._prefix     = None

        # Compiler defaults.
        self._backend    = "c"
        self._defines    = []
        self._flags      = []

        # Option defaults.
        self._keep_going = False
        self._list_only  = False
        self._no_action  = False

        # Package defaults.
        self._actions  = []
        self._packages = []

        # Target defaults.
        self._target = None

        # Capture command-line arguments.
        args = (args or sys.argv)[:]
        args = [arg for arg in args if arg]
        self._parse_args(args)

    def main(self):
        "Carry-out the requested command"
        command = self._command(self.m3neos(), self.package_db())
        command.set_options(self)
        command.execute()

    def m3neos(self):
        if not self._m3neos:
            self._m3neos = M3N(
                script=self._script,
                backend=self._backend,
                defines=self._defines,
                flags=self._flags,
                target=self._target
            )
            self._m3neos.set_options(self)
        return self._m3neos

    def package_db(self):
        if not self._package_db:
            self._package_db = PackageDatabase(self.m3neos())
        return self._package_db

    def _parse_args(self, args):
        "Try to make sense of command-line arguments"

        help = ["-?", "-h", "--help"]
        for item in help:
            if item in args:
                show_usage()
                sys.exit(0)

        self._script = args.pop(0)
        self._parse_command(args)

    def _parse_command(self, args):
        "Identify requested command and parse arguments"

        commands = {
            "boot":   BootCommand,
            "bin" :   BinCommand,
            "src":    SrcCommand,
            "add":    AddCommand
        }

        constructor = None
        for arg in args:
            if arg in commands:
                constructor = commands[arg]
                args.remove(arg)
                break

        if not constructor:
            raise UsageError("no command specified")

        self._command = constructor
        self._command.parse_args(args, self)


# Start here.
if __name__ == "__main__":
    try:
        Package().main()
    except FatalError as err:
        print(f"{err.message}")
    except UsageError as err:
        print(f"{err.message}\n")
        show_usage()
