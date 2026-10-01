using System;
using System.Collections;
using System.IO;
using System.Linq;
using ICSharpCode.Decompiler;
using ICSharpCode.Decompiler.CSharp;
using ICSharpCode.Decompiler.Metadata;
using ICSharpCode.Decompiler.TypeSystem;

class Program
{
    static int Main(string[] args)
    {
        if (args.Length < 2) { Console.Error.WriteLine("usage: dumper <asm> <search|type|res> <arg> [outfile]"); return 2; }
        string asm = args[0], mode = args[1], arg = args.Length > 2 ? args[2] : null;
        string valFilter = args.Length > 4 ? args[4] : null;
        var settings = new DecompilerSettings(LanguageVersion.CSharp10_0) { ThrowOnAssemblyResolveErrors = false };
        if (mode == "res")
        {
            var pe = new PEFile(asm);
            Console.WriteLine("# " + pe.FullName);
            foreach (var r in pe.Resources)
            {
                if (arg != null && r.Name.IndexOf(arg, StringComparison.OrdinalIgnoreCase) < 0) continue;
                Console.WriteLine("== " + r.Name);
                if (!r.Name.EndsWith(".resources")) continue;
                var stream = r.TryOpenStream();
                if (stream == null) { Console.WriteLine("   (no stream)"); continue; }
                try
                {
                    using var rr = new System.Resources.ResourceReader(stream);
                    int n = 0;
                    foreach (DictionaryEntry e in rr)
                    {
                        n++;
                        bool hot = r.Name.IndexOf(arg ?? "###", StringComparison.OrdinalIgnoreCase) >= 0;
                        if (valFilter == null) { if (hot) Console.WriteLine("    key: " + e.Key); }
                        else if (Convert.ToString(e.Key).IndexOf(valFilter, StringComparison.OrdinalIgnoreCase) >= 0) Console.WriteLine("    " + e.Key + " = " + (e.Value is string vs ? vs : e.Value?.ToString()));
                    }
                    Console.WriteLine("    (" + n + " entries)");
                }
                catch (Exception ex) { Console.WriteLine("    ERR " + ex.GetType().Name + ": " + ex.Message); }
            }
            return 0;
        }
        var dec = new CSharpDecompiler(asm, settings);
        string outp = null;
        var sw = new StringWriter();
        if (mode == "search")
        {
            foreach (var t in dec.TypeSystem.MainModule.TypeDefinitions.OrderBy(x => x.FullName))
                if (t.FullName.IndexOf(arg, StringComparison.OrdinalIgnoreCase) >= 0) sw.WriteLine(t.FullName);
        }
        else if (mode == "type")
        {
            sw.WriteLine(dec.DecompileTypeAsString(new FullTypeName(arg)));
        }
        else if (mode == "whole")
        {
            sw.Write(dec.DecompileWholeModuleAsString());
        }
        else { Console.Error.WriteLine("bad mode"); return 2; }
        if (args.Length > 3) { File.WriteAllText(args[3], sw.ToString()); Console.WriteLine("wrote " + args[3] + " (" + sw.ToString().Length + " chars)"); }
        else Console.Write(sw.ToString());
        return 0;
    }
}
