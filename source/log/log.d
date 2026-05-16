import std.format : format;

pragma(inline, true)
string error(string msg)
{
    return format("\033[1m\033[91mx\033[0m %s", msg);
}

pragma(inline, true)
string warn(string msg)
{
    return format("\033[1m\033[93m⚠\033[0m %s", msg);
}

pragma(inline, true)
string ok(string msg)
{
    return format("\033[1m\033[92m✔\033[0m %s", msg);
}

pragma(inline, true)
string done(string msg)
{
    return format("\033[1m\033[32m✔\033[0m %s", msg);
}

pragma(inline, true)
string info(string msg)
{
    return format("\033[1m\033[94m→\033[0m %s", msg);
}

pragma(inline, true)
string pick(string msg)
{
    return format("\033[1;36m→\033[0m %s", msg);
}

pragma(inline, true)
string option(string msg)
{
    return format("\033[1;30m→\033[0m %s", msg);
}
