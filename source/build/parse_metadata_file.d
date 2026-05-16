import std.string : split, strip, indexOf;
import std.array : replace;

string[string] parse_metadata(string content)
{
    string[string] vars;
    string[] keys;

    foreach (entry; split(content, ";"))
    {
        auto eqIdx = indexOf(entry, "=");
        if (eqIdx == -1)
            continue;

        auto key = strip(entry[0 .. eqIdx]);
        auto value = strip(entry[eqIdx + 1 .. $]);

        if (value.length >= 2 && value[0] == '"' && value[$ - 1] == '"')
        {
            value = value[1 .. $ - 1];
        }

        if (key.length == 0)
            continue;

        if (key !in vars)
            keys ~= key;

        vars[key] = value;
    }

    foreach (k; keys)
    {
        string v = vars[k];
        foreach (k2; keys)
        {
            v = v.replace("{{{" ~ k2 ~ "}}}", vars[k2]);
        }
        vars[k] = v;
    }

    string[string] ordered;
    foreach (k; keys)
        ordered[k] = vars[k];

    return ordered;
}
