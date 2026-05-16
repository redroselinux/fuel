import std.stdio;
import std.format : format;
import std.algorithm : startsWith;
import core.stdc.stdlib : exit;
import build;
import log;

void main(string[] args)
{
    auto argc = args.length;

    if (argc == 1)
    {
        writeln(error("No command specified. Use -h to show a help message."));
        exit(2);
    }
    else
    {
        if (args[1] == "-h" || args[1] == "--help")
        {
            writeln("fuel - a source based package manager behind car");
            writeln();
            writeln(info("build [-S --skip-on-fail - skip when package fails to build]"));
            writeln(option("      [-v --verbose]     - show verbose output"));
            writeln(option("      <packages>         - packages to build"));
            writeln(pick("fuel build -S hello gcc libsigsegv"));
            exit(0);
        }
        if (args[1] == "build")
        {
            if (argc < 3)
            {
                writeln(error("You must specify a package."));
                exit(2);
            }
            bool skip_on_error = false;
            bool verbose = false;
            int failed = 0;
            int partial_failed = 0;
            int packages = 0;
            int built = 0;
            foreach (i, arg; args[2 .. $])
            {
                if (arg.startsWith("-")) // flags
                {
                    if (arg == "--skip-on-fail" || arg == "-S")
                        skip_on_error = true;
                    if (arg == "-v" || arg == "--verbose")
                        verbose = true;
                    continue;
                }
                packages += 1;

                int return_ = build_package(arg, verbose);
                if (return_ != 0)
                {
                    if (return_ == 602)
                    { // partial failure
                        writeln(warn(format("Partially failed to build package %s.", arg)));
                        partial_failed += 1;
                        continue;
                    }
                    writeln(error(format("Failed to build package %s.", arg)));
                    failed += 1;
                    if (!skip_on_error)
                        exit(1);
                    writeln(warn(format("Skipping package %s", arg)));
                }
                else
                {
                    built += 1;
                }
            }
            writeln();
            string word;
            if (packages == 1)
                word = "package";
            else
                word = "packages";
            writeln(done(format("Finished compiling %d %s.", packages, word)));
            writeln(option(format("%d failed, %d partially failed, %d suceeded", failed, partial_failed, built)));
        }
        else
        {
            writeln(error(format("Command unknown: %s", args[1])));
            exit(2);
        }
    }
}
