import std.file;
import std.stdio;
import std.array;
import std.process : execute, wait, executeShell;
import std.format : format;
import std.path : expandTilde;
import std.string : indexOf, replace, split, join;
import std.algorithm : startsWith;
import log;
import parse_metadata_file;

int build_package(string name, bool verbose)
{
    bool partial_failure = false;

    if (!(exists("fuelpkgs") && isDir("fuelpkgs")))
    {
        writeln(error("You must have a fuelpkgs directory cloned."));
        return 1;
    }

    if (!(exists("fuelpkgs/" ~ name) && isDir("fuelpkgs/" ~ name)))
    {
        writeln(error(format("Package %s does not exist.", name)));
        return 1;
    }

    if (!(exists("fuelpkgs/" ~ name ~ "/metadata")) &&
        !(isFile("fuelpkgs/" ~ name ~ "/metadata")))
    {
        writeln(error(format("Package %s does not have metadata.", name)));
        return 1;
    }

    writeln(info("Parsing metadata of " ~ name));
    string[string] metadata = parse_metadata(readText("fuelpkgs/" ~ name ~ "/metadata"));
    string source;
    if (auto p = "PackageSource" in metadata)
    {
        source = *p;
    }
    else
    {
        writeln(error("Required variable PackageSource not found!"));
        return 1;
    }
    string sourcesig;
    bool skip = false;
    if (auto p = "PackageSourceSig" in metadata)
    {
        sourcesig = *p;
    }
    else
    {
        // skip verification
        skip = true;
    }

    writeln(info("Downloading: " ~ source));
    string filename = source.split("/")[source.split("/").length - 1];
    if (verbose)
        writeln(format("verbose: %s", filename));
    auto download_process = execute([
        "curl", "-Lo", expandTilde("~/.cache/" ~ filename), source
    ]);
    if (verbose)
        writeln("verbose: " ~ download_process.output);
    if (download_process.status != 0)
    {
        writeln(error(format("Failed to download with error code %d", download_process.status)));
        return 1;
    }

    if (!skip)
    {
        writeln(info("Downloading: " ~ sourcesig));
        string sig_filename = sourcesig.split("/")[$ - 1];
        if (verbose)
            writeln(format("verbose: %s", sig_filename));
        auto sig_download_process = execute([
            "curl", "-Lo", expandTilde("~/.cache/" ~ sig_filename), sourcesig
        ]);
        if (verbose)
            writeln("verbose: " ~ sig_download_process.output);
        if (sig_download_process.status != 0)
        {
            writeln(error(format("Failed to download with error code %d", sig_download_process
                    .status)));
            return 1;
        }

        writeln(info("Verifying signature"));

        auto verify_process = execute([
            "gpg",
            "--verify",
            expandTilde("~/.cache/" ~ sig_filename),
            expandTilde("~/.cache/" ~ filename)
        ]);

        if (verbose)
        {
            writeln("verbose: " ~ verify_process.output);
        }

        if (verify_process.status != 0)
        {
            if (verify_process.output.indexOf("No public key"))
            {
                writeln(error("Missing GPG public key"));
            }
            else
            {
                writeln(error("Signature verification failed"));
            }

            return 1;
        }
    }

    writeln(info("Extracting " ~ filename));
    string working_dir = "fuelpkgs/" ~ name ~ "/" ~ name ~ "-compiling";
    if (filename.indexOf(".tar"))
    {
        try
        {
            rmdirRecurse(working_dir);
        }
        catch (Exception e)
        {
            // dir isnt existing; continue
        }
        mkdir(working_dir);
        auto tar_process = execute([
            "tar", "-xvf",
            expandTilde("~/.cache/" ~ filename), "-C",
            working_dir, "--strip-components=1"
        ]);
        if (verbose)
            writeln("verbose: " ~ tar_process.output);
        if (tar_process.status != 0)
        {
            writeln(error("Failed to extract"));
            return 1;
        }
    }
    else
    {
        writeln(error("Support for this format is not yet added."));
        return 1;
    }

    string buildsystem;
    if (auto p = "BuildSystem" in metadata)
    {
        buildsystem = *p;
    }
    else
    {
        writeln(error("Required variable BuildSystem not found!"));
        return 1;
    }

    chdir(working_dir);
    if (exists("package"))
    {
        rmdirRecurse("package");
    }
    mkdir("package");

    if (buildsystem.startsWith("autoconf"))
    {
        if (buildsystem.startsWith("autoconf-reconf"))
        {
            writeln(info("Reconfiguring autoconf"));
            auto reconf = execute(["autoreconf", "-i"]);
            if (verbose)
                writeln("verbose: " ~ reconf.output);
            if (reconf.status != 0)
            {
                writeln(error("Reconfiguring failed."));
                return 1;
            }

        }

        bool at_configureopts = false;
        bool at_makeopts = false;
        string makeopts;
        string configureopts;
        foreach (word; buildsystem.split)
        {
            if (word == ">>")
            {
                at_configureopts = false;
                at_makeopts = false;
            }
            if (word == "CONFIGUREOPTS")
            {
                at_configureopts = true;
                continue;
            }
            if (word == "MAKEOPTS")
            {
                at_makeopts = true;
                continue;
            }

            if (at_makeopts)
                makeopts ~= word ~ " ";
            if (at_configureopts)
            {
                if (word == "<<RedroseStandardConfigureOpts>>")
                {
                    configureopts ~=
                        "--prefix=/usr --disable-systemd --disable-selinux --disable-apparmor";
                }
                else
                {
                    configureopts ~= word ~ " ";
                }
            }
        }
        writeln(info("Running: ./configure " ~ configureopts));
        auto configure = execute(["./configure"] ~ configureopts.split);
        if (verbose)
            writeln("verbose: " ~ configure.output);
        if (configure.status != 0)
        {
            string[] last_10_lines = configure.output.split("\n")[configure.output.split("\n")
                    .length - 11 .. $];
            writeln(last_10_lines.join("\n"));
            writeln(error("Failed to run configure."));
            return 1;
        }

        writeln(info("Running: make " ~ makeopts));
        auto make = execute(["make"] ~ makeopts.split);
        if (verbose)
            writeln("verbose: " ~ make.output);
        if (make.status != 0)
        {
            string[] last_10_lines = make.output.split("\n")[make.output.split("\n")
                    .length - 11 .. $];
            writeln(last_10_lines.join("\n"));
            writeln(error("Failed to run make."));
            return 1;
        }
    }
    else if (buildsystem.startsWith("custom"))
    {
        buildsystem = buildsystem.replace("custom ", "");
        writeln(info("Running: " ~ buildsystem));
        if (executeShell(buildsystem).status != 0)
        {
            writeln(error("Failed to run custom build commands."));
            return 1;
        }
    }
    else
    {
        writeln(error("Unknown build system. Try using 'custom'."));
        return 1;
    }

    string buildsystem_install;
    if (auto p = "BuildSystem.InstallCommand" in metadata)
    {
        buildsystem_install = *p;
    }
    else
    {
        writeln(error("Required variable BuildSystem.InstallCommand not found!"));
        return 1;
    }

    string dest = getcwd() ~ "/package";
    if (exists(dest))
    {
        rmdirRecurse(dest);
    }
    mkdir(dest);

    string install_cmd_str = buildsystem_install.replace("--DESTINATION--", dest);

    writeln(info("Running: " ~ install_cmd_str));
    auto install_process = executeShell(install_cmd_str);

    if (verbose)
        writeln("verbose: " ~ install_process.output);

    if (install_process.status != 0)
    {
        writeln(error("Failed to run install."));
        return 1;
    }

    writeln(info("Stripping binaries"));
    foreach (string entry; dirEntries(dest, SpanMode.depth))
    {
        if (!isFile(entry) || isSymlink(entry) || getSize(entry) < 4)
            continue;

        auto f = File(entry, "r");
        ubyte[4] magic;
        f.rawRead(magic);
        f.close();

        if (magic == [0x7F, 0x45, 0x4C, 0x46])
        {
            if (verbose)
                writeln("verbose: strip --strip-unneeded " ~ entry);

            auto strip_process = execute([
                "strip", "--strip-unneeded", "-R", ".note.gnu.build-id", entry
            ]);

            if (strip_process.status != 0)
            {
                writeln(warn("Failed to strip: " ~ entry));
                partial_failure = true;
            }
        }
    }

    writeln(info("Creating Car package"));
    string pkgversion;
    if (auto p = "PackageVersion" in metadata)
    {
        pkgversion = *p;
    }
    else
    {
        writeln(error("Required variable PackageVersion not found!"));
        return 1;
    }
    string pkgdeps;
    if (auto p = "PackageDeps" in metadata)
    {
        pkgdeps = *p;
    }
    else
    {
        writeln(error("Required variable PackageDeps not found!"));
        return 1;
    }
    string pkg_metadata = "version " ~ pkgversion ~ "\ndep " ~ pkgdeps.split.join("\n ");
    File pkg_metadata_file = File(dest ~ "/car", "w");
    pkg_metadata_file.writeln(pkg_metadata);
    pkg_metadata_file.close();

    // i hate reproducibility
    auto touch_process = execute([
        "find",
        "package",
        "-exec",
        "touch",
        "-h",
        "-d",
        "@0",
        "{}",
        "+"
    ]);

    if (verbose)
        writeln("verbose:" ~ touch_process.output);

    if (touch_process.status != 0)
    {
        writeln(error("Touch normalization failed!"));
        return 1;
    }

    auto tar_cf_process = execute([
        "fakeroot",
        "tar",
        "--sort=name",
        "--mtime=@0",
        "--owner=0",
        "--group=0",
        "--numeric-owner",
        "--pax-option=delete=atime,delete=ctime",
        "--format=pax",
        "-I", "zstd -T1 --no-progress", // T1 to make sure they are same
        "-cvf",
        "../" ~ name ~ ".tar.zst",
        "package/"
    ]);
    if (verbose)
        writeln("verbose:" ~ tar_cf_process.output);
    if (tar_cf_process.status != 0)
    {
        writeln(error("Creating tar archive failed!"));
        return 1;
    }

    // go back
    chdir("../../../");

    if (partial_failure)
        return 602; // app.d takes this as a partial failure
    return 0;
}
