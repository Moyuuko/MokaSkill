using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

internal static class MokaSkillConfig
{
    private const string EnvBegin = "# >>> Moka Skill managed block >>>";
    private const string EnvEnd = "# <<< Moka Skill managed block <<<";
    private const string IlBegin = "; >>> Moka Skill managed block >>>";
    private const string IlEnd = "; <<< Moka Skill managed block <<<";
    private const string StateFile = "install-state.txt";

    private static readonly string[] MokaEnvLines =
    {
        "# Moka Skill shortcuts",
        "alias F11 moka_ta",
        "alias F12 mokaskill",
        "alias minfo moka_info",
        "alias malign moka_align",
        "alias aa moka_align",
        "alias msbc moka_spread_between_clines",
        "alias mpinswap moka_pin_swap",
        "alias ps moka_pin_swap",
        "alias mdpa moka_dp_antipad",
        "alias msymbols moka_symbols",
        "alias mplace moka_symbols_place",
        "alias mcopper moka_copper_corner",
        "alias mqc moka_quick_copper",
        "alias msi moka_stackup_impedance",
        "alias mclean moka_clean_logs",
        "alias malleft moka_al_left",
        "alias al moka_al_left",
        "alias malright moka_al_right",
        "alias ar moka_al_right",
        "alias maltop moka_al_top",
        "alias at moka_al_top",
        "alias malbot moka_al_bottom",
        "alias ab moka_al_bottom",
        "alias malhc moka_al_hcenter",
        "alias ac moka_al_hcenter",
        "alias malvc moka_al_vcenter",
        "alias av moka_al_vcenter",
        "alias malhd moka_al_hdist",
        "alias ad moka_al_hdist",
        "alias malvd moka_al_vdist",
        "alias as moka_al_vdist",
        "alias malgrid moka_al_grid",
        "alias maldrag moka_al_drag",
        "funckey Z moka_prev",
        "funckey X moka_next",
        "funckey S moka_all",
        "funckey B moka_mode",
        "funckey V moka_via",
        "funckey W moka_width",
        "funckey D moka_quick_copper"
    };

    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 3 && Same(args[0], "install"))
            {
                Install(args[1], args[2]);
                return 0;
            }
            if (args.Length == 2 && Same(args[0], "uninstall"))
            {
                Uninstall(args[1]);
                return 0;
            }
            if (args.Length == 1 && Same(args[0], "self-test"))
            {
                SelfTest();
                return 0;
            }

            Console.Error.WriteLine("Usage: MokaSkillConfig install <install-dir> <SPB_Data-HOME>");
            Console.Error.WriteLine("       MokaSkillConfig uninstall <install-dir>");
            return 2;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Moka Skill configuration failed: " + ex.Message);
            return 1;
        }
    }

    private static void Install(string installDir, string homeDir)
    {
        installDir = FullPath(installDir);
        homeDir = FullPath(homeDir);
        string pcbenvDir = Path.Combine(homeDir, "pcbenv");
        Directory.CreateDirectory(installDir);
        Directory.CreateDirectory(pcbenvDir);

        EnsureMokaEnv(Path.Combine(installDir, "moka.env"), installDir);

        string skillPath = installDir.Replace('\\', '/').Replace("\"", "\\\"");
        ConfigureFile(
            Path.Combine(pcbenvDir, "env"),
            EnvBegin,
            EnvEnd,
            new[] { "source \"" + skillPath + "/moka.env\"" },
            delegate(string line) { return IsLegacyEnvLine(line, installDir); });

        ConfigureFile(
            Path.Combine(pcbenvDir, "allegro.ilinit"),
            IlBegin,
            IlEnd,
            new[]
            {
                "axlSetVariable(\"MOKA_INSTALL_DIR\" \"" + skillPath + "\")",
                "setSkillPath(cons(\"" + skillPath + "\" getSkillPath()))",
                "load(\"moka_loader.il\")"
            },
            delegate(string line) { return IsLegacyIlinitLine(line, installDir); });

        File.WriteAllText(Path.Combine(installDir, StateFile), homeDir + Environment.NewLine, new UTF8Encoding(false));
        Console.WriteLine("Configured Moka Skill for " + pcbenvDir);
    }

    private static void Uninstall(string installDir)
    {
        installDir = FullPath(installDir);
        string statePath = Path.Combine(installDir, StateFile);
        if (!File.Exists(statePath))
        {
            Console.WriteLine("No install state found; external Allegro configuration was not changed.");
            return;
        }

        string homeDir = File.ReadAllText(statePath, Encoding.UTF8).Trim();
        if (homeDir.Length == 0) return;
        string pcbenvDir = Path.Combine(homeDir, "pcbenv");

        RemoveConfiguration(
            Path.Combine(pcbenvDir, "env"), EnvBegin, EnvEnd,
            delegate(string line) { return IsLegacyEnvLine(line, installDir); });
        RemoveConfiguration(
            Path.Combine(pcbenvDir, "allegro.ilinit"), IlBegin, IlEnd,
            delegate(string line) { return IsLegacyIlinitLine(line, installDir); });

        Console.WriteLine("Removed Moka Skill configuration from " + pcbenvDir);
    }

    private static void EnsureMokaEnv(string path, string installDir)
    {
        List<string> lines = ReadLines(path);
        string bitmapPath = installDir.Replace('\\', '/').Replace("\"", "\\\"") +
            "/mooretronics-symbols/icons";
        int oldLineCount = lines.Count;
        lines.RemoveAll(delegate(string line)
        {
            string value = line.Trim().Replace('\\', '/');
            return (value.StartsWith("set bitmappath", StringComparison.OrdinalIgnoreCase) ||
                    value.StartsWith("set bmppath", StringComparison.OrdinalIgnoreCase)) &&
                value.IndexOf("/mooretronics-symbols/icons", StringComparison.OrdinalIgnoreCase) >= 0;
        });
        var normalized = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (string line in lines) normalized.Add(Normalize(line));

        bool changed = !File.Exists(path) || lines.Count != oldLineCount;
        string bitmapPathLine = "set bmppath = \"" + bitmapPath + "\"";
        if (!normalized.Contains(Normalize(bitmapPathLine)))
        {
            lines.Insert(0, bitmapPathLine);
            normalized.Add(Normalize(bitmapPathLine));
            changed = true;
        }
        foreach (string required in MokaEnvLines)
        {
            if (required.StartsWith("#", StringComparison.Ordinal) || normalized.Contains(Normalize(required))) continue;
            if (lines.Count > 0 && String.IsNullOrWhiteSpace(lines[lines.Count - 1])) lines.RemoveAt(lines.Count - 1);
            lines.Add(required);
            normalized.Add(Normalize(required));
            changed = true;
        }
        if (changed) WriteLines(path, lines, Encoding.ASCII);
    }

    private static void ConfigureFile(
        string path, string beginMarker, string endMarker, IEnumerable<string> managedLines,
        Predicate<string> removeLegacy)
    {
        Encoding encoding = DetectEncoding(path);
        List<string> lines = StripManagedAndLegacy(ReadLines(path), beginMarker, endMarker, removeLegacy);
        TrimTrailingBlankLines(lines);
        if (lines.Count > 0) lines.Add(String.Empty);
        lines.Add(beginMarker);
        lines.AddRange(managedLines);
        lines.Add(endMarker);
        WriteLines(path, lines, encoding);
    }

    private static void RemoveConfiguration(
        string path, string beginMarker, string endMarker, Predicate<string> removeLegacy)
    {
        if (!File.Exists(path)) return;
        Encoding encoding = DetectEncoding(path);
        List<string> original = ReadLines(path);
        List<string> clean = StripManagedAndLegacy(original, beginMarker, endMarker, removeLegacy);
        TrimTrailingBlankLines(clean);
        if (!SameLines(original, clean)) WriteLines(path, clean, encoding);
    }

    private static List<string> StripManagedAndLegacy(
        List<string> input, string beginMarker, string endMarker, Predicate<string> removeLegacy)
    {
        var result = new List<string>();
        bool inBlock = false;
        foreach (string line in input)
        {
            if (line.Trim().Equals(beginMarker, StringComparison.OrdinalIgnoreCase))
            {
                inBlock = true;
                continue;
            }
            if (inBlock)
            {
                if (line.Trim().Equals(endMarker, StringComparison.OrdinalIgnoreCase)) inBlock = false;
                continue;
            }
            if (!removeLegacy(line)) result.Add(line);
        }
        CollapseBlankLines(result);
        return result;
    }

    private static bool IsLegacyEnvLine(string line, string installDir)
    {
        string value = line.Trim();
        if (value.IndexOf("Moka Skill Native Sourcing", StringComparison.OrdinalIgnoreCase) >= 0) return true;
        if (Regex.IsMatch(value, "^source\\s+\\\"?[^\\\"]*moka\\.env\\\"?\\s*$", RegexOptions.IgnoreCase)) return true;
        if (value.IndexOf("MENUPATH", StringComparison.OrdinalIgnoreCase) >= 0 &&
            (value.IndexOf("Moka_Skill", StringComparison.OrdinalIgnoreCase) >= 0 || ContainsPath(value, installDir))) return true;
        return false;
    }

    private static bool IsLegacyIlinitLine(string line, string installDir)
    {
        string value = line.Trim();
        if (value.IndexOf("Moka Skill startup", StringComparison.OrdinalIgnoreCase) >= 0) return true;
        if (value.IndexOf("MOKA_INSTALL_DIR", StringComparison.OrdinalIgnoreCase) >= 0) return true;
        if (Regex.IsMatch(value, "load\\(\\\"moka_(?:loader|core)\\.il[e]?\\\"", RegexOptions.IgnoreCase)) return true;
        if (value.IndexOf("setSkillPath", StringComparison.OrdinalIgnoreCase) >= 0 &&
            (value.IndexOf("Moka_Skill", StringComparison.OrdinalIgnoreCase) >= 0 || ContainsPath(value, installDir))) return true;
        return false;
    }

    private static bool ContainsPath(string line, string path)
    {
        string slash = path.Replace('\\', '/');
        return line.IndexOf(path, StringComparison.OrdinalIgnoreCase) >= 0 ||
               line.Replace('\\', '/').IndexOf(slash, StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static List<string> ReadLines(string path)
    {
        return File.Exists(path)
            ? new List<string>(File.ReadAllLines(path, DetectEncoding(path)))
            : new List<string>();
    }

    private static Encoding DetectEncoding(string path)
    {
        if (!File.Exists(path)) return Encoding.Default;
        byte[] bytes = File.ReadAllBytes(path);
        if (bytes.Length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) return new UTF8Encoding(true);
        if (bytes.Length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) return new UnicodeEncoding(false, true);
        if (bytes.Length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) return new UnicodeEncoding(true, true);
        try
        {
            new UTF8Encoding(false, true).GetString(bytes);
            foreach (byte b in bytes) if (b >= 0x80) return new UTF8Encoding(false);
        }
        catch (DecoderFallbackException) { }
        return Encoding.Default;
    }

    private static void WriteLines(string path, List<string> lines, Encoding encoding)
    {
        string parent = Path.GetDirectoryName(path);
        if (!String.IsNullOrEmpty(parent)) Directory.CreateDirectory(parent);
        string content = lines.Count == 0 ? String.Empty : String.Join("\r\n", lines.ToArray()) + "\r\n";
        File.WriteAllText(path, content, encoding);
    }

    private static void CollapseBlankLines(List<string> lines)
    {
        for (int i = lines.Count - 1; i > 0; i--)
            if (String.IsNullOrWhiteSpace(lines[i]) && String.IsNullOrWhiteSpace(lines[i - 1])) lines.RemoveAt(i);
    }

    private static void TrimTrailingBlankLines(List<string> lines)
    {
        while (lines.Count > 0 && String.IsNullOrWhiteSpace(lines[lines.Count - 1])) lines.RemoveAt(lines.Count - 1);
    }

    private static bool SameLines(List<string> left, List<string> right)
    {
        if (left.Count != right.Count) return false;
        for (int i = 0; i < left.Count; i++) if (!String.Equals(left[i], right[i], StringComparison.Ordinal)) return false;
        return true;
    }

    private static string Normalize(string value)
    {
        return Regex.Replace(value.Trim(), "\\s+", " ");
    }

    private static string FullPath(string value)
    {
        if (String.IsNullOrWhiteSpace(value)) throw new ArgumentException("A required path is empty.");
        return Path.GetFullPath(value.Trim());
    }

    private static bool Same(string left, string right)
    {
        return String.Equals(left, right, StringComparison.OrdinalIgnoreCase);
    }

    private static void SelfTest()
    {
        string root = Path.Combine(Path.GetTempPath(), "MokaSkillConfigTest-" + Guid.NewGuid().ToString("N"));
        string app = Path.Combine(root, "Moka Skill");
        string home = Path.Combine(root, "SPB_Data");
        try
        {
            Directory.CreateDirectory(app);
            Directory.CreateDirectory(Path.Combine(home, "pcbenv"));
            File.WriteAllText(
                Path.Combine(app, "moka.env"),
                "set bitmappath = $bitmappath \"" +
                    app.Replace('\\', '/') + "/mooretronics-symbols/icons\"\r\n",
                Encoding.ASCII);
            File.WriteAllText(Path.Combine(home, "pcbenv", "env"), "source $TELENV\r\nset keep = yes\r\n", Encoding.ASCII);
            File.WriteAllText(Path.Combine(home, "pcbenv", "allegro.ilinit"), "; keep me\r\n", Encoding.ASCII);
            Install(app, home);
            Install(app, home);

            string env = File.ReadAllText(Path.Combine(home, "pcbenv", "env"));
            string ilinit = File.ReadAllText(Path.Combine(home, "pcbenv", "allegro.ilinit"));
            string mokaEnv = File.ReadAllText(Path.Combine(app, "moka.env"));
            if (Count(env, EnvBegin) != 1 || Count(ilinit, IlBegin) != 1) throw new Exception("Install is not idempotent.");
            if (env.IndexOf("set keep = yes", StringComparison.Ordinal) < 0 || ilinit.IndexOf("keep me", StringComparison.Ordinal) < 0)
                throw new Exception("Existing user configuration was not preserved.");
            if (mokaEnv.IndexOf("funckey D moka_quick_copper", StringComparison.Ordinal) < 0)
                throw new Exception("Shift+D quick-copper shortcut was not installed.");
            if (mokaEnv.IndexOf("alias msymbols moka_symbols", StringComparison.Ordinal) < 0 ||
                mokaEnv.IndexOf("alias mplace moka_symbols_place", StringComparison.Ordinal) < 0)
                throw new Exception("Mooretronics Symbols Moka commands were not installed.");
            string expectedBitmapPath = "set bmppath = \"" +
                app.Replace('\\', '/') + "/mooretronics-symbols/icons\"";
            if (mokaEnv.IndexOf(expectedBitmapPath, StringComparison.Ordinal) < 0)
                throw new Exception("Mooretronics Symbols BMPPATH was not installed.");
            if (mokaEnv.IndexOf("set bitmappath", StringComparison.OrdinalIgnoreCase) >= 0)
                throw new Exception("Obsolete BITMAPPATH configuration was not removed.");

            Uninstall(app);
            env = File.ReadAllText(Path.Combine(home, "pcbenv", "env"));
            ilinit = File.ReadAllText(Path.Combine(home, "pcbenv", "allegro.ilinit"));
            if (env.IndexOf(EnvBegin, StringComparison.Ordinal) >= 0 || ilinit.IndexOf(IlBegin, StringComparison.Ordinal) >= 0)
                throw new Exception("Uninstall left a managed block behind.");
            if (env.IndexOf("set keep = yes", StringComparison.Ordinal) < 0 || ilinit.IndexOf("keep me", StringComparison.Ordinal) < 0)
                throw new Exception("Uninstall removed user configuration.");
            Console.WriteLine("Self-test passed.");
        }
        finally
        {
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }

    private static int Count(string value, string token)
    {
        int count = 0;
        for (int at = 0; (at = value.IndexOf(token, at, StringComparison.Ordinal)) >= 0; at += token.Length) count++;
        return count;
    }
}
