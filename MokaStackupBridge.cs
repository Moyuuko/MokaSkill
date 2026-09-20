using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Xml;

internal static class MokaStackupBridge
{
    private const string SpreadsheetNamespace = "urn:schemas-microsoft-com:office:spreadsheet";
    private const string FormatName = "Moka Stackup Impedance";
    private const string FormatVersion = "3";
    private const string ReferenceSheetName = "\u53e0\u5c42\u963b\u6297";

    private static readonly string[] MetadataHeaders =
    {
        "Kind", "Order", "Sheet Row", "Name", "Layer Type", "Raw Value", "Raw XML"
    };

    private sealed class StackupRow
    {
        public int Order;
        public readonly Dictionary<string, string> Values =
            new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    }

    private sealed class PhysicalLayerValue
    {
        public double WidthMil;
        public double GapMil;
    }

    private sealed class PhysicalCSetData
    {
        public string Name;
        public readonly Dictionary<string, PhysicalLayerValue> Layers =
            new Dictionary<string, PhysicalLayerValue>(StringComparer.OrdinalIgnoreCase);
    }

    private static int Main(string[] args)
    {
        string logPath = null;
        try
        {
            if ((args.Length == 3 || args.Length == 4) &&
                String.Equals(args[0], "export", StringComparison.OrdinalIgnoreCase))
            {
                if (args.Length == 4) logPath = args[3];
                var exportedPath = ExportWorkbook(args[1], args[2]);
                WriteLog(logPath, "OK|" + exportedPath);
                return 0;
            }

            if ((args.Length == 6 || args.Length == 7) &&
                String.Equals(args[0], "import", StringComparison.OrdinalIgnoreCase))
            {
                if (args.Length == 7) logPath = args[6];
                ImportWorkbook(
                    args[1], args[2], args[3], ParseSwitch(args[4]), ParseSwitch(args[5]));
                WriteLog(logPath, "OK");
                return 0;
            }

            Console.Error.WriteLine(
                "Usage: MokaStackupBridge export <source.tcf> <output.xml> | " +
                "import <workbook.xml> <base.tcf> <output.tcf> <replaceStackup> <replaceImpedance>");
            return 2;
        }
        catch (Exception ex)
        {
            WriteLog(logPath, ex.Message);
            Console.Error.WriteLine(ex.Message);
            return 1;
        }
    }

    private static void WriteLog(string path, string message)
    {
        if (String.IsNullOrWhiteSpace(path)) return;
        File.WriteAllText(path, message + Environment.NewLine, Encoding.GetEncoding(936));
    }

    private static bool ParseSwitch(string value)
    {
        return value == "1" || String.Equals(value, "true", StringComparison.OrdinalIgnoreCase);
    }

    private static XmlDocument LoadXml(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("\u627e\u4e0d\u5230\u6587\u4ef6\u3002", path);
        var document = new XmlDocument { PreserveWhitespace = true, XmlResolver = null };
        try
        {
            using (var stream = new FileStream(
                path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                document.Load(stream);
        }
        catch (IOException ex)
        {
            throw new IOException(
                "\u6587\u4ef6\u6b63\u88ab\u5176\u4ed6\u7a0b\u5e8f\u5360\u7528\uff0c\u65e0\u6cd5\u8bfb\u53d6\u3002\u8bf7\u4fdd\u5b58\u6216\u5173\u95ed\u6587\u4ef6\u540e\u91cd\u8bd5\uff1a" + path,
                ex);
        }
        return document;
    }

    private static XmlElement Child(XmlNode parent, string localName)
    {
        if (parent == null) return null;
        foreach (XmlNode child in parent.ChildNodes)
        {
            var element = child as XmlElement;
            if (element != null && element.LocalName == localName) return element;
        }
        return null;
    }

    private static IEnumerable<XmlElement> Children(XmlNode parent, string localName)
    {
        if (parent == null) yield break;
        foreach (XmlNode child in parent.ChildNodes)
        {
            var element = child as XmlElement;
            if (element != null && element.LocalName == localName) yield return element;
        }
    }

    private static XmlElement Descendant(XmlNode parent, string localName)
    {
        if (parent == null) return null;
        foreach (XmlNode child in parent.ChildNodes)
        {
            var element = child as XmlElement;
            if (element == null) continue;
            if (element.LocalName == localName) return element;
            var found = Descendant(element, localName);
            if (found != null) return found;
        }
        return null;
    }

    private static string ElementText(XmlNode parent, string childName)
    {
        var child = Child(parent, childName);
        return child == null ? String.Empty : child.InnerText.Trim();
    }

    private static bool IsWholeFileFormat(XmlDocument document)
    {
        return document != null && document.DocumentElement != null &&
               document.DocumentElement.LocalName.IndexOf(
                   "root-Cadence-Allegro-Technology-File", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static string NamedAttribute(XmlElement element, string name)
    {
        if (element == null || !element.HasAttribute(name)) return String.Empty;
        return element.GetAttribute(name).Trim();
    }

    private static string AttributeName(XmlElement attribute)
    {
        var name = NamedAttribute(attribute, "Name");
        return name.Length > 0 ? name : ElementText(attribute, "name");
    }

    private static string AttributeValue(XmlElement attribute)
    {
        var value = Child(attribute, "value");
        if (value == null) return String.Empty;
        return value.HasAttribute("Value") ? value.GetAttribute("Value").Trim() : value.InnerText.Trim();
    }

    private static string LayerAttribute(XmlElement layer, string attributeName)
    {
        foreach (var attribute in Children(layer, "attribute"))
        {
            if (String.Equals(AttributeName(attribute), attributeName, StringComparison.OrdinalIgnoreCase))
                return AttributeValue(attribute);
        }
        return String.Empty;
    }

    private static void SetLayerAttribute(
        XmlDocument document, XmlElement layer, string attributeName, string value)
    {
        XmlElement match = null;
        foreach (var attribute in Children(layer, "attribute"))
        {
            if (String.Equals(AttributeName(attribute), attributeName, StringComparison.OrdinalIgnoreCase))
            {
                match = attribute;
                break;
            }
        }

        if (String.IsNullOrWhiteSpace(value))
        {
            if (match != null) layer.RemoveChild(match);
            return;
        }

        if (match == null)
        {
            var modern = layer.LocalName == "object";
            match = document.CreateElement("attribute", layer.NamespaceURI);
            var val = document.CreateElement("value", layer.NamespaceURI);
            if (modern)
            {
                match.SetAttribute("Name", attributeName);
                val.SetAttribute("Value", value.Trim());
                var origin = document.CreateElement("origin", layer.NamespaceURI);
                var originValue = document.CreateElement("v", layer.NamespaceURI);
                originValue.InnerText = "BE";
                origin.AppendChild(originValue);
                match.AppendChild(val);
                match.AppendChild(origin);
            }
            else
            {
                var name = document.CreateElement("name");
                name.InnerText = attributeName;
                var origin = document.CreateElement("Origin");
                origin.InnerText = "gBackEnd";
                match.AppendChild(name);
                match.AppendChild(val);
                match.AppendChild(origin);
            }
            var objectFlag = Child(layer, "objectFlag");
            if (objectFlag == null) layer.AppendChild(match);
            else layer.InsertBefore(match, objectFlag);
        }

        var valueElement = Child(match, "value");
        if (valueElement == null)
        {
            valueElement = document.CreateElement("value", layer.NamespaceURI);
            match.AppendChild(valueElement);
        }
        if (layer.LocalName == "object") valueElement.SetAttribute("Value", value.Trim());
        else valueElement.InnerText = value.Trim();
    }

    private static void SetLayerName(XmlDocument document, XmlElement layer, string name)
    {
        if (layer.LocalName == "object")
        {
            SetLayerAttribute(document, layer, "CDS_LAYER_NAME", name);
            return;
        }
        var nameElement = Child(layer, "name");
        if (nameElement == null)
        {
            nameElement = document.CreateElement("name");
            layer.PrependChild(nameElement);
        }
        nameElement.InnerText = name;
    }

    private static string LayerName(XmlElement layer)
    {
        return layer != null && layer.LocalName == "object"
            ? LayerAttribute(layer, "CDS_LAYER_NAME") : ElementText(layer, "name");
    }

    private static string LayerType(XmlElement layer)
    {
        if (layer == null) return String.Empty;
        var type = LayerAttribute(layer, "CDS_LAYER_TYPE");
        if (type.Length == 0) type = NamedAttribute(layer, "Type");
        if (type.Length == 0) type = LayerAttribute(layer, "CDS_LAYER_FUNCTION");
        type = type.Replace("_", String.Empty).ToUpperInvariant();
        if (type == "SOLDERMASK") return "MASK";
        return type;
    }

    private static XmlElement CrossSectionContainer(XmlDocument document)
    {
        var crossSection = Descendant(document.DocumentElement, "crossSection");
        if (crossSection != null) return crossSection;
        var xSection = Descendant(document.DocumentElement, "x-section");
        return Child(xSection, "children");
    }

    private static List<XmlElement> LayerElements(XmlDocument document)
    {
        var container = CrossSectionContainer(document);
        if (container == null) throw new InvalidDataException("\u6280\u672f\u6587\u4ef6\u4e2d\u7f3a\u5c11\u53e0\u5c42\u622a\u9762\u6570\u636e\u3002");
        var result = new List<XmlElement>();
        foreach (XmlNode child in container.ChildNodes)
        {
            var element = child as XmlElement;
            if (element == null) continue;
            if (element.LocalName == "layer" ||
                (element.LocalName == "object" && NamedAttribute(element, "Type").Length > 0))
                result.Add(element);
        }
        return result;
    }

    private static XmlElement ObjectsSection(XmlDocument document, string name)
    {
        if (document == null || document.DocumentElement == null) return null;
        var pending = new Queue<XmlNode>();
        pending.Enqueue(document.DocumentElement);
        while (pending.Count > 0)
        {
            var node = pending.Dequeue();
            foreach (XmlNode child in node.ChildNodes)
            {
                var element = child as XmlElement;
                if (element == null) continue;
                if (element.LocalName == "xml-objects" &&
                    String.Equals(NamedAttribute(element, "Name"), name, StringComparison.OrdinalIgnoreCase))
                    return element;
                pending.Enqueue(element);
            }
        }
        return null;
    }

    private static XmlElement PhysicalCSetContainer(XmlDocument document)
    {
        var constraints = Descendant(document.DocumentElement, "constraints");
        if (constraints != null) return constraints;
        return Child(ObjectsSection(document, "PhysicalCSet"), "root");
    }

    private static List<XmlElement> PhysicalCSetElements(XmlDocument document)
    {
        var container = PhysicalCSetContainer(document);
        var result = new List<XmlElement>();
        if (container == null) return result;
        foreach (XmlNode child in container.ChildNodes)
        {
            var element = child as XmlElement;
            if (element != null && (element.LocalName == "physicalCSet" || element.LocalName == "object"))
                result.Add(element);
        }
        return result;
    }

    private static string ObjectName(XmlElement element)
    {
        var name = NamedAttribute(element, "Name");
        return name.Length > 0 ? name : ElementText(element, "name");
    }

    private static void SetObjectName(XmlDocument document, XmlElement element, string name)
    {
        if (element.LocalName == "object") element.SetAttribute("Name", name);
        else SetLayerName(document, element, name);
    }

    private static string GetUnits(XmlDocument document)
    {
        var precision = Descendant(document.DocumentElement, "precision");
        var units = NamedAttribute(precision, "units");
        if (units.Length == 0) units = ElementText(precision, "units");
        return String.IsNullOrWhiteSpace(units) ? "design units" : units;
    }

    private static string GetTechnologyVersion(XmlDocument document)
    {
        var header = Descendant(document.DocumentElement, "technologyHeader");
        var version = ElementText(Child(header, "version"), "value");
        if (version.Length > 0) return version;
        var formatVersion = Descendant(document.DocumentElement, "txt-FormatVersion");
        if (formatVersion == null)
        {
            var pending = new Queue<XmlNode>();
            pending.Enqueue(document.DocumentElement);
            while (pending.Count > 0 && formatVersion == null)
            {
                var node = pending.Dequeue();
                foreach (XmlNode child in node.ChildNodes)
                {
                    var element = child as XmlElement;
                    if (element == null) continue;
                    if (String.Equals(NamedAttribute(element, "Name"), "FormatVersion", StringComparison.OrdinalIgnoreCase))
                    {
                        formatVersion = element;
                        break;
                    }
                    pending.Enqueue(element);
                }
            }
        }
        return formatVersion == null ? String.Empty : formatVersion.InnerText.Trim();
    }

    private static bool SupportsSolderMaskLayers(XmlDocument document)
    {
        var version = ExtractFirstNumber(GetTechnologyVersion(document));
        return !Double.IsNaN(version) && version >= 17.4;
    }

    private static string ExportWorkbook(string tcfPath, string workbookPath)
    {
        var document = LoadXml(tcfPath);

        var stackupRows = new List<Dictionary<string, string>>();
        var order = 1;
        foreach (var layer in LayerElements(document))
        {
            var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            row["Order"] = order.ToString(CultureInfo.InvariantCulture);
            row["Layer Name"] = LayerName(layer);
            row["Layer Type"] = LayerType(layer);
            row["Material"] = LayerAttribute(layer, "CDS_LAYER_MATERIAL");
            row["Thickness"] = LayerAttribute(layer, "CDS_LAYER_THICKNESS");
            row["Dielectric Constant"] = LayerAttribute(layer, "CDS_LAYER_DIELECTRIC_CONSTANT");
            row["Loss Tangent"] = LayerAttribute(layer, "CDS_LAYER_LOSS_TANGENT");
            row["Electrical Conductivity"] = LayerAttribute(layer, "CDS_LAYER_ELECTRICAL_CONDUCTIVITY");
            row["Thermal Conductivity"] = LayerAttribute(layer, "CDS_LAYER_THERMAL_CONDUCTIVITY");
            row["Negative Artwork"] = LayerAttribute(layer, "CDS_LAYER_NEGATIVE_ARTWORK");
            row["Shield"] = LayerAttribute(layer, "CDS_LAYER_IS_SHIELD");
            row["Etch Factor"] = LayerAttribute(layer, "CDS_LAYER_ETCH_FACTOR");
            row["Raw XML"] = layer.OuterXml;
            stackupRows.Add(row);
            order++;
        }

        var units = GetUnits(document);
        var etchLayers = GetEtchLayerNames(document);
        var physicalCsets = ReadPhysicalCsets(document, etchLayers, units);
        return WriteWorkbook(workbookPath, units, stackupRows, physicalCsets);
    }

    private static string WriteWorkbook(
        string path,
        string units,
        IList<Dictionary<string, string>> stackupRows,
        IList<PhysicalCSetData> physicalCsets)
    {
        var visibleStackup = new List<Dictionary<string, string>>();
        foreach (var row in stackupRows)
            if (IncludeReferenceLayer(row)) visibleStackup.Add(row);

        var conductorIndexes = new List<int>();
        for (var i = 0; i < visibleStackup.Count; i++)
        {
            var type = Value(visibleStackup[i], "Layer Type").ToUpperInvariant();
            if (type == "CONDUCTOR" || type == "PLANE") conductorIndexes.Add(i);
            visibleStackup[i]["Sheet Row"] = (i + 3).ToString(CultureInfo.InvariantCulture);
        }
        for (var i = 0; i < conductorIndexes.Count; i++)
        {
            visibleStackup[conductorIndexes[i]]["Style Role"] =
                i == 0 || i == conductorIndexes.Count - 1 ? "OuterCopper" : "InnerCopper";
        }
        foreach (var row in visibleStackup)
        {
            if (Value(row, "Style Role").Length > 0) continue;
            var name = Value(row, "Layer Name");
            var material = Value(row, "Material");
            if (IsSolderMask(name, material)) row["Style Role"] = "SolderMask";
            else if (name.IndexOf("CORE", StringComparison.OrdinalIgnoreCase) >= 0 ||
                     name.IndexOf("MIDDLE", StringComparison.OrdinalIgnoreCase) >= 0)
                row["Style Role"] = "Core";
            else row["Style Role"] = "Prepreg";
        }

        var lastStackRow = visibleStackup.Count + 2;
        var gridLastRow = lastStackRow;
        var totalMil = 0.0;
        foreach (var row in visibleStackup)
            totalMil += ToMil(ParseDouble(Value(row, "Thickness"), 0.0), units);
        var totalMm = totalMil * 0.0254;

        var metadata = new List<Dictionary<string, string>>();
        metadata.Add(MetaRow("META", "0", "0", "Format", "", FormatName, ""));
        metadata.Add(MetaRow("META", "0", "0", "Version", "", FormatVersion, ""));
        metadata.Add(MetaRow("META", "0", "0", "Units", "", units, ""));
        metadata.Add(MetaRow("META", "0", "0", "VisibleSheet", "", ReferenceSheetName, ""));
        foreach (var row in stackupRows)
        {
            var sheetRow = Value(row, "Sheet Row");
            if (sheetRow.Length == 0) sheetRow = "0";
            metadata.Add(MetaRow(
                "STACK", Value(row, "Order"), sheetRow,
                Value(row, "Layer Name"), Value(row, "Layer Type"),
                Value(row, "Thickness"), Value(row, "Raw XML")));
        }
        var settings = new XmlWriterSettings
        {
            Encoding = new UTF8Encoding(false),
            Indent = true,
            NewLineChars = "\r\n"
        };

        var fullPath = Path.GetFullPath(path);
        var directory = Path.GetDirectoryName(fullPath);
        if (!String.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        var tempPath = Path.Combine(
            directory ?? String.Empty,
            "." + Path.GetFileName(fullPath) + "." + Guid.NewGuid().ToString("N") + ".tmp");
        using (var writer = XmlWriter.Create(tempPath, settings))
        {
            writer.WriteStartDocument();
            writer.WriteStartElement("Workbook", SpreadsheetNamespace);
            writer.WriteAttributeString("xmlns", "ss", null, SpreadsheetNamespace);
            writer.WriteAttributeString("xmlns", "x", null, "urn:schemas-microsoft-com:office:excel");
            WriteStyles(writer);

            WriteReferenceWorksheet(
                writer, visibleStackup, physicalCsets, units,
                conductorIndexes.Count, totalMil, totalMm, gridLastRow);
            WriteWorksheet(writer, "_MokaMeta", MetadataHeaders, metadata, true, true);

            writer.WriteEndElement();
            writer.WriteEndDocument();
        }
        return CommitWorkbook(tempPath, fullPath);
    }

    private static string CommitWorkbook(string tempPath, string requestedPath)
    {
        try
        {
            try
            {
                if (File.Exists(requestedPath)) File.Replace(tempPath, requestedPath, null);
                else File.Move(tempPath, requestedPath);
                return requestedPath;
            }
            catch (IOException)
            {
                var alternate = BuildAlternateWorkbookPath(requestedPath);
                File.Move(tempPath, alternate);
                return alternate;
            }
            catch (UnauthorizedAccessException)
            {
                var alternate = BuildAlternateWorkbookPath(requestedPath);
                File.Move(tempPath, alternate);
                return alternate;
            }
        }
        finally
        {
            if (File.Exists(tempPath)) File.Delete(tempPath);
        }
    }

    private static string BuildAlternateWorkbookPath(string requestedPath)
    {
        var directory = Path.GetDirectoryName(requestedPath) ?? String.Empty;
        var stem = Path.GetFileNameWithoutExtension(requestedPath);
        var extension = Path.GetExtension(requestedPath);
        var stamp = DateTime.Now.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
        var candidate = Path.Combine(directory, stem + "_" + stamp + extension);
        var suffix = 2;
        while (File.Exists(candidate))
        {
            candidate = Path.Combine(directory,
                stem + "_" + stamp + "_" + suffix.ToString(CultureInfo.InvariantCulture) + extension);
            suffix++;
        }
        return candidate;
    }

    private static Dictionary<string, string> MetaRow(
        string kind, string order, string sheetRow, string name,
        string layerType, string rawValue, string rawXml)
    {
        return Row(
            "Kind", kind, "Order", order, "Sheet Row", sheetRow, "Name", name,
            "Layer Type", layerType, "Raw Value", rawValue, "Raw XML", rawXml);
    }

    private static bool IncludeReferenceLayer(Dictionary<string, string> row)
    {
        var type = Value(row, "Layer Type").ToUpperInvariant();
        var material = Value(row, "Material");
        var thickness = ParseDouble(Value(row, "Thickness"), 0.0);
        if (type == "SURFACE" && thickness <= 0.0) return false;
        if (String.Equals(material, "AIR", StringComparison.OrdinalIgnoreCase) && thickness <= 0.0) return false;
        return true;
    }

    private static bool IsSolderMask(string name, string material)
    {
        return name.IndexOf("SOLDER", StringComparison.OrdinalIgnoreCase) >= 0 ||
               name.IndexOf("MASK", StringComparison.OrdinalIgnoreCase) >= 0 ||
               name.IndexOf("ABOVE_TOP", StringComparison.OrdinalIgnoreCase) >= 0 ||
               name.IndexOf("BELOW_BOTTOM", StringComparison.OrdinalIgnoreCase) >= 0 ||
               material.IndexOf("SOLDER", StringComparison.OrdinalIgnoreCase) >= 0 ||
               material.IndexOf("MASK", StringComparison.OrdinalIgnoreCase) >= 0 ||
               material.IndexOf("COAT", StringComparison.OrdinalIgnoreCase) >= 0;
    }

    private static double ParseDouble(string value, double defaultValue)
    {
        double result;
        return Double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out result)
            ? result : defaultValue;
    }

    private static double ToMil(double value, string units)
    {
        var normalized = (units ?? String.Empty).Trim().ToLowerInvariant();
        if (normalized == "mm" || normalized.IndexOf("millimeter", StringComparison.Ordinal) >= 0)
            return value / 0.0254;
        if (normalized == "inch" || normalized.IndexOf("inch", StringComparison.Ordinal) >= 0)
            return value * 1000.0;
        if (normalized == "micron" || normalized == "um") return value / 25.4;
        return value;
    }

    private static double FromMil(double value, string units)
    {
        var normalized = (units ?? String.Empty).Trim().ToLowerInvariant();
        if (normalized == "mm" || normalized.IndexOf("millimeter", StringComparison.Ordinal) >= 0)
            return value * 0.0254;
        if (normalized == "inch" || normalized.IndexOf("inch", StringComparison.Ordinal) >= 0)
            return value / 1000.0;
        if (normalized == "micron" || normalized == "um") return value * 25.4;
        return value;
    }

    private static bool IsOhmPhysicalCSetName(string name)
    {
        return !String.IsNullOrWhiteSpace(name) &&
               name.Trim().EndsWith("OHM", StringComparison.OrdinalIgnoreCase);
    }

    private static List<string> GetEtchLayerNames(XmlDocument document)
    {
        var result = new List<string>();
        foreach (var layer in LayerElements(document))
        {
            var type = LayerType(layer);
            if (type == "CONDUCTOR" || type == "PLANE") result.Add(LayerName(layer));
        }
        if (result.Count == 0) throw new InvalidDataException("\u6280\u672f\u6587\u4ef6\u4e2d\u6ca1\u6709 ETCH \u5c42\u3002");
        return result;
    }

    private static List<string> ReadConstraintArray(string value, int count)
    {
        var result = new List<string>();
        if (!String.IsNullOrWhiteSpace(value))
        {
            foreach (var item in value.Split(',')) result.Add(item.Trim());
        }
        if (result.Count == 1 && count > 1)
            while (result.Count < count) result.Add(result[0]);
        while (result.Count < count) result.Add("0");
        if (result.Count > count) result.RemoveRange(count, result.Count - count);
        return result;
    }

    private static List<PhysicalCSetData> ReadPhysicalCsets(
        XmlDocument document, IList<string> etchLayers, string units)
    {
        var result = new List<PhysicalCSetData>();
        foreach (var cset in PhysicalCSetElements(document))
        {
            var name = ObjectName(cset);
            if (!IsOhmPhysicalCSetName(name)) continue;
            var widths = ReadConstraintArray(LayerAttribute(cset, "MIN_LINE_WIDTH"), etchLayers.Count);
            var gaps = ReadConstraintArray(LayerAttribute(cset, "DIFFP_PRIMARY_GAP"), etchLayers.Count);
            var data = new PhysicalCSetData { Name = name };
            for (var i = 0; i < etchLayers.Count; i++)
            {
                var width = ParseDouble(widths[i], Double.NaN);
                if (Double.IsNaN(width) || width <= 0.0) continue;
                var gap = ParseDouble(gaps[i], 0.0);
                data.Layers[etchLayers[i]] = new PhysicalLayerValue
                {
                    WidthMil = ToMil(width, units),
                    GapMil = gap > 0.0 ? ToMil(gap, units) : 0.0
                };
            }
            result.Add(data);
        }
        result.Sort(delegate(PhysicalCSetData left, PhysicalCSetData right)
        {
            var leftOhm = ExtractFirstNumber(left.Name);
            var rightOhm = ExtractFirstNumber(right.Name);
            if (!Double.IsNaN(leftOhm) && !Double.IsNaN(rightOhm))
            {
                var numberCompare = leftOhm.CompareTo(rightOhm);
                if (numberCompare != 0) return numberCompare;
            }
            return StringComparer.OrdinalIgnoreCase.Compare(left.Name, right.Name);
        });
        if (result.Count > 6)
            throw new InvalidDataException("\u53c2\u8003\u8868\u683c\u6700\u591a\u652f\u6301 6 \u4e2a\u4ee5 ohm \u7ed3\u5c3e\u7684 Physical CSet\u3002");
        return result;
    }

    private static string FormatDimension(double value)
    {
        return Math.Abs(value - Math.Round(value)) < 0.0001
            ? Math.Round(value).ToString(CultureInfo.InvariantCulture)
            : value.ToString("0.###", CultureInfo.InvariantCulture);
    }

    private static void WriteReferenceWorksheet(
        XmlWriter writer,
        IList<Dictionary<string, string>> stackupRows,
        IList<PhysicalCSetData> physicalCsets,
        string units,
        int conductorCount,
        double totalMil,
        double totalMm,
        int gridLastRow)
    {
        var stackByRow = new Dictionary<int, Dictionary<string, string>>();
        foreach (var row in stackupRows)
            stackByRow[Int32.Parse(Value(row, "Sheet Row"), CultureInfo.InvariantCulture)] = row;

        writer.WriteStartElement("Worksheet", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Name", SpreadsheetNamespace, ReferenceSheetName);
        writer.WriteStartElement("Table", SpreadsheetNamespace);
        foreach (var width in new[] { 38, 109, 94, 74, 47, 14, 14, 89, 95, 65, 65, 65, 65, 65 })
            WriteColumn(writer, width);

        writer.WriteStartElement("Row", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Height", SpreadsheetNamespace, "30");
        WriteCellEx(writer,
            conductorCount.ToString(CultureInfo.InvariantCulture) + "\u5c42\u901a\u5b54 " +
            totalMm.ToString("0.00", CultureInfo.InvariantCulture) + "mm",
            "Title", "String", 1, 1, null);
        WriteCellEx(writer, "Impedance", "ImpHeader", "String", 8, 0, null);
        for (var i = 0; i < 6; i++)
            WriteCellEx(writer, i < physicalCsets.Count ? physicalCsets[i].Name : "",
                "ImpHeader", "String", 0, 0, null);
        writer.WriteEndElement();

        writer.WriteStartElement("Row", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Height", SpreadsheetNamespace, "33");
        foreach (var header in new[]
        {
            "Layer", "Mother Board", "Typical layer thickness (mil)", "Dielectric Constant", "DF"
        }) WriteCellEx(writer, header, "Header", "String", 0, 0, null);
        WriteCellEx(writer, "Reference Layer", "ImpHeader", "String", 8, 0, null);
        WriteCellEx(writer, "Design W(mil)", "ImpHeader", "String", 0, 0, null);
        for (var i = 1; i < 6; i++) WriteCellEx(writer, "", "ImpHeader", "String", 0, 0, null);
        writer.WriteEndElement();

        var totalRow = stackupRows.Count + 3;
        var mmRow = totalRow + 1;
        var maxRow = Math.Max(mmRow, gridLastRow);
        for (var excelRow = 3; excelRow <= maxRow; excelRow++)
        {
            writer.WriteStartElement("Row", SpreadsheetNamespace);
            writer.WriteAttributeString("ss", "Height", SpreadsheetNamespace, "20.25");
            Dictionary<string, string> stack;
            if (stackByRow.TryGetValue(excelRow, out stack))
            {
                var type = Value(stack, "Layer Type").ToUpperInvariant();
                var layerName = type == "CONDUCTOR" || type == "PLANE" ? Value(stack, "Layer Name") : "";
                var material = IsSolderMask(Value(stack, "Layer Name"), Value(stack, "Material"))
                    ? "Solder Mask" : Value(stack, "Material");
                var role = Value(stack, "Style Role");
                WriteCellEx(writer, layerName, "Grid", "String", 0, 0, null);
                WriteCellEx(writer, material, role + "Text", "String", 0, 0, null);
                WriteCellEx(writer,
                    ToMil(ParseDouble(Value(stack, "Thickness"), 0.0), units).ToString("0.###", CultureInfo.InvariantCulture),
                    role + "Num2", "Number", 0, 0, null);
                var isCopper = type == "CONDUCTOR" || type == "PLANE";
                WriteMaybeNumberCell(writer,
                    isCopper ? String.Empty : Value(stack, "Dielectric Constant"), role + "Num2");
                WriteMaybeNumberCell(writer,
                    isCopper ? String.Empty : Value(stack, "Loss Tangent"), role + "Num3");
            }
            else if (excelRow == totalRow)
            {
                WriteCellEx(writer, totalMil.ToString("0.###", CultureInfo.InvariantCulture),
                    "TotalMil", "Number", 3, 0,
                    "=SUM(R3C3:R" + (totalRow - 1).ToString(CultureInfo.InvariantCulture) + "C3)");
            }
            else if (excelRow == mmRow)
            {
                WriteCellEx(writer, totalMm.ToString("0.#####", CultureInfo.InvariantCulture),
                    "TotalMm", "Number", 3, 0, "=R[-1]C*0.0254");
            }

            if (excelRow <= gridLastRow)
            {
                var routeLayer = String.Empty;
                if (stack != null)
                {
                    var type = Value(stack, "Layer Type").ToUpperInvariant();
                    if (type == "CONDUCTOR" || type == "PLANE")
                    {
                        var candidate = Value(stack, "Layer Name");
                        foreach (var cset in physicalCsets)
                            if (cset.Layers.ContainsKey(candidate))
                            {
                                routeLayer = candidate;
                                break;
                            }
                    }
                }
                WriteCellEx(writer, physicalCsets.Count > 0 ? routeLayer : "",
                    routeLayer.Length > 0 ? "ImpRef" : "Grid", "String", 8, 0, null);
                for (var i = 0; i < 6; i++)
                {
                    var display = String.Empty;
                    PhysicalLayerValue value;
                    if (routeLayer.Length > 0 && i < physicalCsets.Count &&
                        physicalCsets[i].Layers.TryGetValue(routeLayer, out value))
                        display = FormatPhysicalValue(value);
                    WriteCellEx(writer, display, display.Length > 0 ? "ImpValue" : "Grid",
                        "String", 0, 0, null);
                }
            }
            writer.WriteEndElement();
        }

        writer.WriteEndElement();
        writer.WriteStartElement("WorksheetOptions", "urn:schemas-microsoft-com:office:excel");
        writer.WriteElementString("DoNotDisplayGridlines", "urn:schemas-microsoft-com:office:excel", "");
        writer.WriteEndElement();
        writer.WriteEndElement();
    }

    private static string FormatPhysicalValue(PhysicalLayerValue value)
    {
        var width = FormatDimension(value.WidthMil);
        return value.GapMil > 0.0 ? width + "->" + FormatDimension(value.GapMil) : width;
    }

    private static void WriteColumn(XmlWriter writer, int width)
    {
        writer.WriteStartElement("Column", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "AutoFitWidth", SpreadsheetNamespace, "0");
        writer.WriteAttributeString("ss", "Width", SpreadsheetNamespace, width.ToString(CultureInfo.InvariantCulture));
        writer.WriteEndElement();
    }

    private static Dictionary<string, string> Row(params string[] values)
    {
        var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i + 1 < values.Length; i += 2) row[values[i]] = values[i + 1];
        return row;
    }

    private static void WriteStyles(XmlWriter writer)
    {
        writer.WriteStartElement("Styles", SpreadsheetNamespace);
        WriteStyleDefinition(writer, "Default", null, false, "Left", false, null, false);
        WriteStyleDefinition(writer, "Grid", null, false, "Center", false, null, true);
        WriteStyleDefinition(writer, "Header", null, false, "Center", true, null, true);
        WriteStyleDefinition(writer, "Title", "#FF00FF", true, "Left", false, null, false);
        WriteStyleDefinition(writer, "ImpHeader", null, false, "Center", true, null, true);
        WriteStyleDefinition(writer, "ImpRef", null, true, "Left", false, null, true);
        WriteStyleDefinition(writer, "ImpValue", null, false, "Center", false, null, true);
        WriteStyleDefinition(writer, "TotalMil", null, false, "Center", false, "0.00", false);
        WriteStyleDefinition(writer, "TotalMm", null, false, "Center", false, "0.00", false);
        WriteLayerStyles(writer, "SolderMask", "#00FF00");
        WriteLayerStyles(writer, "OuterCopper", "#FFFF00");
        WriteLayerStyles(writer, "InnerCopper", "#FF6600");
        WriteLayerStyles(writer, "Prepreg", "#99CC00");
        WriteLayerStyles(writer, "Core", "#99CCFF");
        writer.WriteEndElement();
    }

    private static void WriteLayerStyles(XmlWriter writer, string prefix, string color)
    {
        WriteStyleDefinition(writer, prefix + "Text", color, false, "Center", false, null, true);
        WriteStyleDefinition(writer, prefix + "Num2", color, false, "Center", false, "0.00", true);
        WriteStyleDefinition(writer, prefix + "Num3", color, false, "Center", false, "0.000", true);
    }

    private static void WriteStyleDefinition(
        XmlWriter writer, string id, string color, bool bold, string horizontal,
        bool wrap, string numberFormat, bool borders)
    {
        writer.WriteStartElement("Style", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "ID", SpreadsheetNamespace, id);
        writer.WriteStartElement("Alignment", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Vertical", SpreadsheetNamespace, "Center");
        writer.WriteAttributeString("ss", "Horizontal", SpreadsheetNamespace, horizontal);
        if (wrap) writer.WriteAttributeString("ss", "WrapText", SpreadsheetNamespace, "1");
        writer.WriteEndElement();
        writer.WriteStartElement("Font", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "FontName", SpreadsheetNamespace, "Calibri");
        writer.WriteAttributeString("ss", "Size", SpreadsheetNamespace, "11");
        if (bold) writer.WriteAttributeString("ss", "Bold", SpreadsheetNamespace, "1");
        writer.WriteEndElement();
        if (!String.IsNullOrEmpty(color))
        {
            writer.WriteStartElement("Interior", SpreadsheetNamespace);
            writer.WriteAttributeString("ss", "Color", SpreadsheetNamespace, color);
            writer.WriteAttributeString("ss", "Pattern", SpreadsheetNamespace, "Solid");
            writer.WriteEndElement();
        }
        if (!String.IsNullOrEmpty(numberFormat))
        {
            writer.WriteStartElement("NumberFormat", SpreadsheetNamespace);
            writer.WriteAttributeString("ss", "Format", SpreadsheetNamespace, numberFormat);
            writer.WriteEndElement();
        }
        if (borders)
        {
            writer.WriteStartElement("Borders", SpreadsheetNamespace);
            foreach (var position in new[] { "Bottom", "Left", "Right", "Top" })
            {
                writer.WriteStartElement("Border", SpreadsheetNamespace);
                writer.WriteAttributeString("ss", "Position", SpreadsheetNamespace, position);
                writer.WriteAttributeString("ss", "LineStyle", SpreadsheetNamespace, "Continuous");
                writer.WriteAttributeString("ss", "Weight", SpreadsheetNamespace, "1");
                writer.WriteEndElement();
            }
            writer.WriteEndElement();
        }
        writer.WriteEndElement();
    }

    private static void WriteWorksheet(
        XmlWriter writer,
        string name,
        IEnumerable<string> headers,
        IList<Dictionary<string, string>> rows,
        bool hidden,
        bool hideRawXml)
    {
        var headerList = new List<string>(headers);
        writer.WriteStartElement("Worksheet", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Name", SpreadsheetNamespace, name);
        if (hidden) writer.WriteAttributeString("ss", "Visible", SpreadsheetNamespace, "SheetHidden");
        writer.WriteStartElement("Table", SpreadsheetNamespace);

        foreach (var header in headerList)
        {
            writer.WriteStartElement("Column", SpreadsheetNamespace);
            writer.WriteAttributeString("ss", "AutoFitWidth", SpreadsheetNamespace, "0");
            writer.WriteAttributeString("ss", "Width", SpreadsheetNamespace,
                header == "Raw XML" ? "30" : (header.Length > 18 ? "120" : "90"));
            if (hideRawXml && header == "Raw XML")
                writer.WriteAttributeString("ss", "Hidden", SpreadsheetNamespace, "1");
            writer.WriteEndElement();
        }

        writer.WriteStartElement("Row", SpreadsheetNamespace);
        foreach (var header in headerList) WriteCell(writer, header, "Header");
        writer.WriteEndElement();

        foreach (var row in rows)
        {
            writer.WriteStartElement("Row", SpreadsheetNamespace);
            foreach (var header in headerList)
            {
                string value;
                row.TryGetValue(header, out value);
                WriteCell(writer, value ?? String.Empty, "Default");
            }
            writer.WriteEndElement();
        }

        writer.WriteEndElement();
        writer.WriteEndElement();
    }

    private static void WriteCell(XmlWriter writer, string value, string style)
    {
        writer.WriteStartElement("Cell", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "StyleID", SpreadsheetNamespace, style);
        writer.WriteStartElement("Data", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Type", SpreadsheetNamespace, "String");
        writer.WriteString(value ?? String.Empty);
        writer.WriteEndElement();
        writer.WriteEndElement();
    }

    private static void WriteMaybeNumberCell(XmlWriter writer, string value, string style)
    {
        double number;
        if (Double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number))
            WriteCellEx(writer, number.ToString(CultureInfo.InvariantCulture), style, "Number", 0, 0, null);
        else
            WriteCellEx(writer, value, style, "String", 0, 0, null);
    }

    private static void WriteCellEx(
        XmlWriter writer, string value, string style, string type,
        int index, int mergeAcross, string formula)
    {
        writer.WriteStartElement("Cell", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "StyleID", SpreadsheetNamespace, style);
        if (index > 0)
            writer.WriteAttributeString("ss", "Index", SpreadsheetNamespace, index.ToString(CultureInfo.InvariantCulture));
        if (mergeAcross > 0)
            writer.WriteAttributeString("ss", "MergeAcross", SpreadsheetNamespace, mergeAcross.ToString(CultureInfo.InvariantCulture));
        if (!String.IsNullOrEmpty(formula))
            writer.WriteAttributeString("ss", "Formula", SpreadsheetNamespace, formula);
        writer.WriteStartElement("Data", SpreadsheetNamespace);
        writer.WriteAttributeString("ss", "Type", SpreadsheetNamespace, type);
        writer.WriteString(value ?? String.Empty);
        writer.WriteEndElement();
        writer.WriteEndElement();
    }

    private static void ImportWorkbook(
        string workbookPath,
        string baseTcfPath,
        string outputTcfPath,
        bool replaceStackup,
        bool replaceImpedance)
    {
        if (!replaceStackup && !replaceImpedance)
            throw new InvalidDataException("\u8bf7\u81f3\u5c11\u9009\u62e9\u5bfc\u5165\u53e0\u5c42\u6216\u963b\u6297\u3002");

        var workbook = LoadXml(workbookPath);
        var document = LoadXml(baseTcfPath);
        if (!IsReferenceLayout(workbook))
            throw new InvalidDataException(
                "\u4e0d\u652f\u6301\u7684\u5de5\u4f5c\u7c3f\u683c\u5f0f\u3002\u7b2c\u4e00\u9875\u5fc5\u987b\u4f7f\u7528\u53c2\u8003\u683c\u5f0f\uff0cLayer \u4f4d\u4e8e A2\uff0cImpedance \u4f4d\u4e8e H1\u3002");

        Dictionary<string, string> templateLayerMap = null;
        if (replaceStackup)
        {
            var oldEtchLayers = GetEtchLayerNames(document);
            var rows = ReadReferenceStackupRows(workbook, document);
            templateLayerMap = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            foreach (var row in rows)
            {
                var templateName = Value(row.Values, "Template Layer Name");
                if (templateName.Length > 0) templateLayerMap[templateName] = Value(row.Values, "Layer Name");
            }
            ReplaceStackup(document, rows);
            ResizePhysicalCSetArrays(document, oldEtchLayers, GetEtchLayerNames(document));
        }

        if (replaceImpedance)
        {
            var csets = ReadReferencePhysicalCsets(workbook, document, templateLayerMap);
            ReplacePhysicalCsets(document, csets);
        }

        SaveDocument(document, outputTcfPath);
    }

    private static void SaveDocument(XmlDocument document, string path)
    {
        var settings = new XmlWriterSettings
        {
            Encoding = new UTF8Encoding(false),
            Indent = true,
            NewLineChars = "\r\n"
        };
        using (var writer = XmlWriter.Create(path, settings)) document.Save(writer);
    }

    private static bool HasWorksheet(XmlDocument workbook, string name)
    {
        foreach (XmlNode node in workbook.GetElementsByTagName("Worksheet", SpreadsheetNamespace))
        {
            var element = node as XmlElement;
            if (element != null && String.Equals(
                element.GetAttribute("Name", SpreadsheetNamespace), name, StringComparison.OrdinalIgnoreCase))
                return true;
        }
        return false;
    }

    private static XmlElement FirstVisibleWorksheet(XmlDocument workbook)
    {
        foreach (XmlNode node in workbook.GetElementsByTagName("Worksheet", SpreadsheetNamespace))
        {
            var element = node as XmlElement;
            if (element == null) continue;
            var visible = element.GetAttribute("Visible", SpreadsheetNamespace);
            if (!String.Equals(visible, "SheetHidden", StringComparison.OrdinalIgnoreCase)) return element;
        }
        return null;
    }

    private static bool IsReferenceLayout(XmlDocument workbook)
    {
        var worksheet = FirstVisibleWorksheet(workbook);
        if (worksheet == null) return false;
        var rows = ReadWorksheetMatrix(worksheet);
        return rows.Count >= 2 && Cell(rows, 1, 0).Equals("Layer", StringComparison.OrdinalIgnoreCase) &&
               Cell(rows, 0, 7).Equals("Impedance", StringComparison.OrdinalIgnoreCase);
    }

    private static List<Dictionary<string, string>> ReadWorksheet(XmlDocument workbook, string name)
    {
        XmlElement worksheet = null;
        foreach (XmlNode node in workbook.GetElementsByTagName("Worksheet", SpreadsheetNamespace))
        {
            var element = node as XmlElement;
            if (element == null) continue;
            var worksheetName = element.GetAttribute("Name", SpreadsheetNamespace);
            if (String.Equals(worksheetName, name, StringComparison.OrdinalIgnoreCase))
            {
                worksheet = element;
                break;
            }
        }
        if (worksheet == null) throw new InvalidDataException("\u7f3a\u5c11\u5de5\u4f5c\u8868\uff1a" + name);

        var table = Child(worksheet, "Table");
        if (table == null) throw new InvalidDataException("\u5de5\u4f5c\u8868\u4e2d\u6ca1\u6709\u8868\u683c\uff1a" + name);
        var rawRows = new List<List<string>>();
        foreach (var row in Children(table, "Row")) rawRows.Add(ReadRow(row));
        if (rawRows.Count == 0) throw new InvalidDataException("\u5de5\u4f5c\u8868\u4e3a\u7a7a\uff1a" + name);

        var headers = rawRows[0];
        var result = new List<Dictionary<string, string>>();
        for (var rowIndex = 1; rowIndex < rawRows.Count; rowIndex++)
        {
            var values = rawRows[rowIndex];
            var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var hasValue = false;
            for (var column = 0; column < headers.Count; column++)
            {
                var header = headers[column].Trim();
                if (header.Length == 0) continue;
                var value = column < values.Count ? values[column].Trim() : String.Empty;
                row[header] = value;
                if (value.Length > 0) hasValue = true;
            }
            if (hasValue) result.Add(row);
        }
        return result;
    }

    private static List<List<string>> ReadWorksheetMatrix(XmlElement worksheet)
    {
        var table = Child(worksheet, "Table");
        if (table == null) throw new InvalidDataException("\u5de5\u4f5c\u8868\u4e2d\u6ca1\u6709\u8868\u683c\u3002");
        var rows = new List<List<string>>();
        foreach (var row in Children(table, "Row")) rows.Add(ReadRow(row));
        return rows;
    }

    private static string Cell(IList<List<string>> rows, int row, int column)
    {
        if (row < 0 || row >= rows.Count || column < 0 || column >= rows[row].Count)
            return String.Empty;
        return (rows[row][column] ?? String.Empty).Trim();
    }

    private static List<string> ReadRow(XmlElement row)
    {
        var result = new List<string>();
        var nextIndex = 1;
        foreach (var cell in Children(row, "Cell"))
        {
            var indexText = cell.GetAttribute("Index", SpreadsheetNamespace);
            int index;
            if (!String.IsNullOrEmpty(indexText) && Int32.TryParse(indexText, out index)) nextIndex = index;
            while (result.Count < nextIndex - 1) result.Add(String.Empty);
            var data = Child(cell, "Data");
            result.Add(data == null ? String.Empty : data.InnerText);
            nextIndex++;
        }
        return result;
    }

    private static string Value(Dictionary<string, string> row, string key)
    {
        string value;
        return row.TryGetValue(key, out value) ? value.Trim() : String.Empty;
    }

    private static List<Dictionary<string, string>> ReadMetadata(XmlDocument workbook, string kind)
    {
        var result = new List<Dictionary<string, string>>();
        if (!HasWorksheet(workbook, "_MokaMeta")) return result;
        foreach (var row in ReadWorksheet(workbook, "_MokaMeta"))
            if (String.Equals(Value(row, "Kind"), kind, StringComparison.OrdinalIgnoreCase)) result.Add(row);
        return result;
    }

    private static string MetadataSetting(XmlDocument workbook, string name)
    {
        foreach (var row in ReadMetadata(workbook, "META"))
            if (String.Equals(Value(row, "Name"), name, StringComparison.OrdinalIgnoreCase))
                return Value(row, "Raw Value");
        return String.Empty;
    }

    private static List<StackupRow> ReadReferenceStackupRows(XmlDocument workbook, XmlDocument baseDocument)
    {
        var worksheet = FirstVisibleWorksheet(workbook);
        var matrix = ReadWorksheetMatrix(worksheet);
        var metadata = ReadMetadata(workbook, "STACK");
        var metaBySheetRow = new Dictionary<int, Dictionary<string, string>>();
        foreach (var meta in metadata)
        {
            int sheetRow;
            if (Int32.TryParse(Value(meta, "Sheet Row"), out sheetRow) && sheetRow > 0)
                metaBySheetRow[sheetRow] = meta;
        }

        var baseLayers = LayerElements(baseDocument);
        var baseByName = new Dictionary<string, XmlElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var layer in baseLayers)
        {
            var baseName = LayerName(layer);
            if (baseName.Length > 0) baseByName[baseName] = layer;
        }

        var visibleSheetRows = new List<int>();
        var importSolderMask = SupportsSolderMaskLayers(baseDocument);
        for (var rowIndex = 2; rowIndex < matrix.Count; rowIndex++)
        {
            var material = Cell(matrix, rowIndex, 1);
            if (material.Length == 0) break;
            if (!importSolderMask && IsSolderMask(String.Empty, material)) continue;
            visibleSheetRows.Add(rowIndex);
        }
        if (visibleSheetRows.Count < 2)
            throw new InvalidDataException("\u53c2\u8003\u5de5\u4f5c\u8868\u4e2d\u6ca1\u6709\u53e0\u5c42\u6570\u636e\u3002");

        var metadataAligned = MetadataMatchesVisibleStackup(matrix, visibleSheetRows, metaBySheetRow);
        var etchRows = new List<int>();
        foreach (var rowIndex in visibleSheetRows)
            if (Cell(matrix, rowIndex, 0).Length > 0) etchRows.Add(rowIndex);
        if (etchRows.Count < 2)
            throw new InvalidDataException("\u53e0\u5c42\u5fc5\u987b\u81f3\u5c11\u5305\u542b\u4e24\u4e2a\u5df2\u547d\u540d\u7684 ETCH \u5c42\u3002");
        var baseEtchNames = new List<string>();
        foreach (var layer in baseLayers)
        {
            var baseType = LayerType(layer);
            if (baseType == "CONDUCTOR" || baseType == "PLANE") baseEtchNames.Add(LayerName(layer));
        }
        if (etchRows.Count < baseEtchNames.Count)
            throw new InvalidDataException(
                "\u6a21\u677f\u7684 ETCH \u5c42\u6570\u5c11\u4e8e\u5f53\u524d\u8bbe\u8ba1\uff0c\u65e0\u6cd5\u5220\u9664\u5df2\u6709\u5e03\u7ebf\u5c42\u3002");
        var actualEtchNames = BuildActualEtchLayerNames(matrix, etchRows, baseEtchNames);
        var firstEtchRow = etchRows[0];
        var lastEtchRow = etchRows[etchRows.Count - 1];

        var units = GetUnits(baseDocument);
        var rows = new List<StackupRow>();
        var usedNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var rowIndex in visibleSheetRows)
        {
            var materialDisplay = Cell(matrix, rowIndex, 1);
            var sheetRow = rowIndex + 1;
            var displayedName = Cell(matrix, rowIndex, 0);
            var isEtch = displayedName.Length > 0;
            var isSolderMask = !isEtch && IsSolderMask(displayedName, materialDisplay);
            Dictionary<string, string> meta = null;
            if (metadataAligned) metaBySheetRow.TryGetValue(sheetRow, out meta);

            var name = isEtch
                ? actualEtchNames[rowIndex]
                : isSolderMask
                    ? BuildSolderMaskLayerName(rowIndex, firstEtchRow, lastEtchRow, usedNames)
                    : BuildDielectricLayerName(rowIndex, visibleSheetRows, actualEtchNames, usedNames);
            XmlElement baseLayer = null;
            if (name.Length > 0) baseByName.TryGetValue(name, out baseLayer);

            var type = String.Empty;
            if (baseLayer != null) type = LayerType(baseLayer);
            if (type.Length == 0 && meta != null) type = Value(meta, "Layer Type").ToUpperInvariant();
            if (isEtch)
                type = "CONDUCTOR";
            else type = isSolderMask ? "MASK" : "DIELECTRIC";

            var rawXml = meta == null ? String.Empty : Value(meta, "Raw XML");
            if (rawXml.Length == 0 && baseLayer != null) rawXml = baseLayer.OuterXml;
            if (rawXml.Length == 0)
            {
                var prototype = SelectLayerPrototype(
                    baseLayers, type, rowIndex == firstEtchRow, rowIndex == lastEtchRow);
                if (prototype != null) rawXml = prototype.OuterXml;
            }

            var stack = new StackupRow();
            stack.Order = rows.Count + 1;
            stack.Values["Order"] = stack.Order.ToString(CultureInfo.InvariantCulture);
            stack.Values["Layer Name"] = name;
            if (isEtch) stack.Values["Template Layer Name"] = displayedName;
            stack.Values["Layer Type"] = type;
            stack.Values["Material"] = isSolderMask ? "POLYIMIDE" : materialDisplay;
            var thicknessMil = ParseDouble(Cell(matrix, rowIndex, 2), Double.NaN);
            if (Double.IsNaN(thicknessMil))
                throw new InvalidDataException("\u53e0\u5c42\u539a\u5ea6\u65e0\u6548\uff0c\u8868\u683c\u884c\uff1a" + sheetRow + "\u3002");
            stack.Values["Thickness"] = FromMil(thicknessMil, units).ToString("0.######", CultureInfo.InvariantCulture);
            stack.Values["Dielectric Constant"] = Cell(matrix, rowIndex, 3);
            stack.Values["Loss Tangent"] = Cell(matrix, rowIndex, 4);
            stack.Values["Raw XML"] = rawXml;
            PopulatePreservedLayerValues(stack.Values, rawXml);
            if (isEtch)
            {
                stack.Values["Top Substrate"] = rowIndex == firstEtchRow ? "1" : String.Empty;
                stack.Values["Bottom Substrate"] = rowIndex == lastEtchRow ? "1" : String.Empty;
            }
            rows.Add(stack);
            usedNames.Add(name);
        }

        var topHidden = new List<StackupRow>();
        var bottomHidden = new List<StackupRow>();
        var seenVisible = false;
        foreach (var layer in baseLayers)
        {
            var probe = StackDictionaryFromLayer(layer, 0);
            if (IncludeReferenceLayer(probe))
            {
                seenVisible = true;
                continue;
            }
            var hidden = StackupRowFromLayer(layer, 0);
            if (seenVisible) bottomHidden.Add(hidden); else topHidden.Add(hidden);
        }

        var combined = new List<StackupRow>();
        combined.AddRange(topHidden);
        combined.AddRange(rows);
        combined.AddRange(bottomHidden);
        rows = combined;
        for (var i = 0; i < rows.Count; i++)
        {
            rows[i].Order = i + 1;
            rows[i].Values["Order"] = (i + 1).ToString(CultureInfo.InvariantCulture);
        }

        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var row in rows)
        {
            var layerName = Value(row.Values, "Layer Name");
            if (layerName.Length > 0 && !names.Add(layerName))
                throw new InvalidDataException("\u53e0\u5c42\u540d\u79f0\u91cd\u590d\uff1a" + layerName);
        }
        return rows;
    }

    private static bool MetadataMatchesVisibleStackup(
        IList<List<string>> matrix, IList<int> visibleRows,
        IDictionary<int, Dictionary<string, string>> metadataBySheetRow)
    {
        if (metadataBySheetRow.Count != visibleRows.Count) return false;
        foreach (var rowIndex in visibleRows)
        {
            Dictionary<string, string> meta;
            if (!metadataBySheetRow.TryGetValue(rowIndex + 1, out meta)) return false;
            var displayedName = Cell(matrix, rowIndex, 0);
            var type = Value(meta, "Layer Type").ToUpperInvariant();
            if (displayedName.Length > 0)
            {
                if (!String.Equals(displayedName, Value(meta, "Name"), StringComparison.OrdinalIgnoreCase)) return false;
                if (type != "CONDUCTOR" && type != "PLANE") return false;
            }
            else if (type == "CONDUCTOR" || type == "PLANE") return false;
        }
        return true;
    }

    private static Dictionary<int, string> BuildActualEtchLayerNames(
        IList<List<string>> matrix, IList<int> etchRows, IList<string> existingNames)
    {
        var result = new Dictionary<int, string>();
        var used = new HashSet<string>(existingNames, StringComparer.OrdinalIgnoreCase);
        result[etchRows[0]] = existingNames[0];
        result[etchRows[etchRows.Count - 1]] = existingNames[existingNames.Count - 1];
        for (var oldIndex = 1; oldIndex < existingNames.Count - 1; oldIndex++)
            result[etchRows[oldIndex]] = existingNames[oldIndex];
        foreach (var rowIndex in etchRows)
        {
            if (result.ContainsKey(rowIndex)) continue;
            var stem = Cell(matrix, rowIndex, 0);
            var name = stem;
            if (used.Contains(name))
            {
                var position = etchRows.IndexOf(rowIndex) + 1;
                name = "L" + position.ToString(CultureInfo.InvariantCulture);
                if (used.Contains(name)) name = "ETCH" + position.ToString("00", CultureInfo.InvariantCulture);
                var suffix = 2;
                var candidate = name;
                while (used.Contains(candidate))
                {
                    candidate = name + "_" + suffix.ToString(CultureInfo.InvariantCulture);
                    suffix++;
                }
                name = candidate;
            }
            result[rowIndex] = name;
            used.Add(name);
        }
        return result;
    }

    private static string BuildDielectricLayerName(
        int rowIndex, IList<int> visibleRows, IDictionary<int, string> actualEtchNames,
        ISet<string> usedNames)
    {
        var previous = String.Empty;
        var next = String.Empty;
        for (var offset = visibleRows.IndexOf(rowIndex) - 1; offset >= 0; offset--)
        {
            if (actualEtchNames.TryGetValue(visibleRows[offset], out previous)) break;
        }
        for (var offset = visibleRows.IndexOf(rowIndex) + 1; offset < visibleRows.Count; offset++)
        {
            if (actualEtchNames.TryGetValue(visibleRows[offset], out next)) break;
        }
        var stem = previous.Length == 0
            ? "DIELECTRIC_ABOVE_" + (next.Length > 0 ? next : "TOP")
            : "DIELECTRIC_BELOW_" + previous;
        var name = stem;
        var suffix = 2;
        while (usedNames.Contains(name))
        {
            name = stem + "_" + suffix.ToString("00", CultureInfo.InvariantCulture);
            suffix++;
        }
        return name;
    }

    private static string BuildSolderMaskLayerName(
        int rowIndex, int firstEtchRow, int lastEtchRow, ISet<string> usedNames)
    {
        var stem = rowIndex < firstEtchRow ? "SOLDERMASK_TOP" :
            rowIndex > lastEtchRow ? "SOLDERMASK_BOTTOM" : "SOLDERMASK";
        var name = stem;
        var suffix = 2;
        while (usedNames.Contains(name))
        {
            name = stem + "_" + suffix.ToString(CultureInfo.InvariantCulture);
            suffix++;
        }
        return name;
    }

    private static XmlElement SelectLayerPrototype(
        IList<XmlElement> baseLayers, string type, bool firstEtch, bool lastEtch)
    {
        if (firstEtch || lastEtch)
        {
            var etch = new List<XmlElement>();
            foreach (var layer in baseLayers)
            {
                var current = LayerType(layer);
                if (current == "CONDUCTOR" || current == "PLANE") etch.Add(layer);
            }
            if (etch.Count > 0) return firstEtch ? etch[0] : etch[etch.Count - 1];
        }
        foreach (var layer in baseLayers)
            if (String.Equals(LayerType(layer), type, StringComparison.OrdinalIgnoreCase))
                return layer;
        if (type == "CONDUCTOR" || type == "PLANE")
            foreach (var layer in baseLayers)
            {
                var current = LayerType(layer);
                if (current == "CONDUCTOR" || current == "PLANE") return layer;
            }
        return null;
    }

    private static Dictionary<string, string> StackDictionaryFromLayer(XmlElement layer, int order)
    {
        var row = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        row["Order"] = order.ToString(CultureInfo.InvariantCulture);
        row["Layer Name"] = LayerName(layer);
        row["Layer Type"] = LayerType(layer);
        row["Material"] = LayerAttribute(layer, "CDS_LAYER_MATERIAL");
        row["Thickness"] = LayerAttribute(layer, "CDS_LAYER_THICKNESS");
        row["Dielectric Constant"] = LayerAttribute(layer, "CDS_LAYER_DIELECTRIC_CONSTANT");
        row["Loss Tangent"] = LayerAttribute(layer, "CDS_LAYER_LOSS_TANGENT");
        row["Electrical Conductivity"] = LayerAttribute(layer, "CDS_LAYER_ELECTRICAL_CONDUCTIVITY");
        row["Thermal Conductivity"] = LayerAttribute(layer, "CDS_LAYER_THERMAL_CONDUCTIVITY");
        row["Negative Artwork"] = LayerAttribute(layer, "CDS_LAYER_NEGATIVE_ARTWORK");
        row["Shield"] = LayerAttribute(layer, "CDS_LAYER_IS_SHIELD");
        row["Etch Factor"] = LayerAttribute(layer, "CDS_LAYER_ETCH_FACTOR");
        row["Raw XML"] = layer.OuterXml;
        return row;
    }

    private static StackupRow StackupRowFromLayer(XmlElement layer, int order)
    {
        var result = new StackupRow { Order = order };
        foreach (var pair in StackDictionaryFromLayer(layer, order)) result.Values[pair.Key] = pair.Value;
        return result;
    }

    private static StackupRow StackupRowFromMetadata(Dictionary<string, string> meta)
    {
        int order;
        if (!Int32.TryParse(Value(meta, "Order"), out order)) order = 0;
        var result = new StackupRow { Order = order };
        result.Values["Order"] = order.ToString(CultureInfo.InvariantCulture);
        result.Values["Layer Name"] = Value(meta, "Name");
        result.Values["Layer Type"] = Value(meta, "Layer Type");
        result.Values["Thickness"] = Value(meta, "Raw Value");
        result.Values["Raw XML"] = Value(meta, "Raw XML");
        PopulatePreservedLayerValues(result.Values, result.Values["Raw XML"]);
        return result;
    }

    private static void PopulatePreservedLayerValues(Dictionary<string, string> values, string rawXml)
    {
        if (String.IsNullOrWhiteSpace(rawXml)) return;
        var fragment = new XmlDocument { XmlResolver = null };
        fragment.LoadXml(rawXml);
        var layer = fragment.DocumentElement;
        if (layer == null || (layer.LocalName != "layer" && layer.LocalName != "object")) return;
        foreach (var pair in new[]
        {
            new[] { "Material", "CDS_LAYER_MATERIAL" },
            new[] { "Dielectric Constant", "CDS_LAYER_DIELECTRIC_CONSTANT" },
            new[] { "Loss Tangent", "CDS_LAYER_LOSS_TANGENT" },
            new[] { "Electrical Conductivity", "CDS_LAYER_ELECTRICAL_CONDUCTIVITY" },
            new[] { "Thermal Conductivity", "CDS_LAYER_THERMAL_CONDUCTIVITY" },
            new[] { "Negative Artwork", "CDS_LAYER_NEGATIVE_ARTWORK" },
            new[] { "Shield", "CDS_LAYER_IS_SHIELD" },
            new[] { "Etch Factor", "CDS_LAYER_ETCH_FACTOR" }
        })
        {
            if (!values.ContainsKey(pair[0]) || String.IsNullOrWhiteSpace(values[pair[0]]))
                values[pair[0]] = LayerAttribute(layer, pair[1]);
        }
    }

    private static List<PhysicalCSetData> ReadReferencePhysicalCsets(
        XmlDocument workbook, XmlDocument document, IDictionary<string, string> templateLayerMap)
    {
        var matrix = ReadWorksheetMatrix(FirstVisibleWorksheet(workbook));
        var etchLayers = GetEtchLayerNames(document);
        var etchNames = new HashSet<string>(etchLayers, StringComparer.OrdinalIgnoreCase);
        var columns = new Dictionary<int, PhysicalCSetData>();
        var result = new List<PhysicalCSetData>();
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (var column = 8; column <= 13; column++)
        {
            var name = Cell(matrix, 0, column);
            if (name.Length == 0) continue;
            if (!IsOhmPhysicalCSetName(name))
                throw new InvalidDataException(
                    "\u7b2c " + (column + 1).ToString(CultureInfo.InvariantCulture) +
                    " \u5217\u7684 Physical CSet \u540d\u79f0\u5fc5\u987b\u4ee5 ohm \u7ed3\u5c3e\u3002");
            if (!names.Add(name)) throw new InvalidDataException("Physical CSet \u5217\u540d\u79f0\u91cd\u590d\uff1a" + name);
            var cset = new PhysicalCSetData { Name = name };
            columns[column] = cset;
            result.Add(cset);
        }

        for (var rowIndex = 2; rowIndex < matrix.Count; rowIndex++)
        {
            var templateLayerName = Cell(matrix, rowIndex, 0);
            var layerName = templateLayerName;
            if (templateLayerMap != null)
            {
                string mappedName;
                if (templateLayerMap.TryGetValue(templateLayerName, out mappedName)) layerName = mappedName;
            }
            if (!etchNames.Contains(layerName)) continue;
            foreach (var pair in columns)
            {
                var display = Cell(matrix, rowIndex, pair.Key);
                if (display.Length == 0) continue;
                pair.Value.Layers[layerName] = ParsePhysicalValue(display, pair.Value.Name, layerName);
            }
        }
        return result;
    }

    private static PhysicalLayerValue ParsePhysicalValue(string display, string csetName, string layerName)
    {
        var normalized = display.Replace(" ", String.Empty).Trim();
        var parts = normalized.Split(new[] { "->" }, StringSplitOptions.None);
        if (parts.Length < 1 || parts.Length > 2)
            throw new InvalidDataException("Physical CSet \u53c2\u6570\u683c\u5f0f\u65e0\u6548\uff1a" + csetName + "\uff0c\u5c42\uff1a" + layerName + "\u3002");
        var width = ParseDouble(parts[0], Double.NaN);
        if (Double.IsNaN(width) || width <= 0.0)
            throw new InvalidDataException("Line Width-Min \u5fc5\u987b\u5927\u4e8e 0\uff0cPhysical CSet\uff1a" + csetName + "\uff0c\u5c42\uff1a" + layerName + "\u3002");
        var gap = 0.0;
        if (parts.Length == 2)
        {
            gap = ParseDouble(parts[1], Double.NaN);
            if (Double.IsNaN(gap) || gap <= 0.0)
                throw new InvalidDataException("Differential Pair Primary Gap \u5fc5\u987b\u5927\u4e8e 0\uff0cPhysical CSet\uff1a" + csetName + "\uff0c\u5c42\uff1a" + layerName + "\u3002");
        }
        return new PhysicalLayerValue { WidthMil = width, GapMil = gap };
    }

    private static double ExtractFirstNumber(string value)
    {
        if (String.IsNullOrWhiteSpace(value)) return Double.NaN;
        var buffer = new StringBuilder();
        var started = false;
        foreach (var character in value)
        {
            if (Char.IsDigit(character) || character == '.')
            {
                buffer.Append(character);
                started = true;
            }
            else if (started) break;
        }
        return ParseDouble(buffer.ToString(), Double.NaN);
    }

    private static XmlElement LayerFromRow(
        XmlDocument document, StackupRow row, bool modern, string namespaceUri)
    {
        XmlElement layer = null;
        var rawXml = Value(row.Values, "Raw XML");
        if (rawXml.Length > 0)
        {
            var fragment = new XmlDocument { XmlResolver = null };
            fragment.LoadXml(rawXml);
            if (fragment.DocumentElement != null &&
                ((!modern && fragment.DocumentElement.LocalName == "layer") ||
                 (modern && fragment.DocumentElement.LocalName == "object")))
                layer = (XmlElement)document.ImportNode(fragment.DocumentElement, true);
        }
        if (layer == null)
            layer = modern ? document.CreateElement("object", namespaceUri) : document.CreateElement("layer");

        var layerType = Value(row.Values, "Layer Type").ToUpperInvariant();
        if (modern)
        {
            var objectType = layerType == "MASK" ? "Mask" :
                layerType == "DIELECTRIC" ? "Dielectric" :
                layerType == "SURFACE" ? "Surface" : "Conductor";
            layer.SetAttribute("Type", objectType);
            SetLayerAttribute(document, layer, "CDS_LAYER_FUNCTION",
                layerType == "MASK" ? "SOLDER_MASK" :
                layerType == "PLANE" ? "CONDUCTOR" : layerType);
        }
        else SetLayerAttribute(document, layer, "CDS_LAYER_TYPE", layerType);
        SetLayerName(document, layer,
            modern && layerType != "CONDUCTOR" && layerType != "PLANE" && layerType != "MASK"
                ? String.Empty : Value(row.Values, "Layer Name"));
        SetLayerAttribute(document, layer, "CDS_LAYER_MATERIAL", Value(row.Values, "Material"));
        SetLayerAttribute(document, layer, "CDS_LAYER_THICKNESS", Value(row.Values, "Thickness"));
        SetLayerAttribute(document, layer, "CDS_LAYER_DIELECTRIC_CONSTANT", Value(row.Values, "Dielectric Constant"));
        SetLayerAttribute(document, layer, "CDS_LAYER_LOSS_TANGENT", Value(row.Values, "Loss Tangent"));
        SetLayerAttribute(document, layer, "CDS_LAYER_ELECTRICAL_CONDUCTIVITY", Value(row.Values, "Electrical Conductivity"));
        SetLayerAttribute(document, layer, "CDS_LAYER_THERMAL_CONDUCTIVITY", Value(row.Values, "Thermal Conductivity"));
        SetLayerAttribute(document, layer, "CDS_LAYER_NEGATIVE_ARTWORK", Value(row.Values, "Negative Artwork"));
        SetLayerAttribute(document, layer, "CDS_LAYER_IS_SHIELD", Value(row.Values, "Shield"));
        SetLayerAttribute(document, layer, "CDS_LAYER_ETCH_FACTOR", Value(row.Values, "Etch Factor"));
        if (modern)
        {
            SetLayerAttribute(document, layer, "CDS_LAYER_THICKNESS_PLUS",
                LayerAttribute(layer, "CDS_LAYER_THICKNESS_PLUS").Length > 0
                    ? LayerAttribute(layer, "CDS_LAYER_THICKNESS_PLUS") : "0");
            SetLayerAttribute(document, layer, "CDS_LAYER_THICKNESS_MINUS",
                LayerAttribute(layer, "CDS_LAYER_THICKNESS_MINUS").Length > 0
                    ? LayerAttribute(layer, "CDS_LAYER_THICKNESS_MINUS") : "0");
            if (layerType == "MASK" || layerType == "DIELECTRIC")
                SetLayerAttribute(document, layer, "CDS_LAYER_ELECTRICAL_CONDUCTIVITY",
                    LayerAttribute(layer, "CDS_LAYER_ELECTRICAL_CONDUCTIVITY").Length > 0
                        ? LayerAttribute(layer, "CDS_LAYER_ELECTRICAL_CONDUCTIVITY") : "0");
        }
        if (layerType == "CONDUCTOR" || layerType == "PLANE")
        {
            SetLayerAttribute(document, layer, "CDS_LAYER_NEGATIVE_ARTWORK", modern ? String.Empty : "FALSE");
            SetLayerAttribute(document, layer, "CDS_LAYER_IS_NAMED", "1");
            SetLayerAttribute(document, layer, "CDS_LAYER_IS_TOP_SUBSTRATE", Value(row.Values, "Top Substrate"));
            SetLayerAttribute(document, layer, "CDS_LAYER_IS_BOTTOM_SUBSTRATE", Value(row.Values, "Bottom Substrate"));
        }
        else
        {
            SetLayerAttribute(document, layer, "CDS_LAYER_IS_TOP_SUBSTRATE", String.Empty);
            SetLayerAttribute(document, layer, "CDS_LAYER_IS_BOTTOM_SUBSTRATE", String.Empty);
        }
        return layer;
    }

    private static void ReplaceStackup(XmlDocument document, IList<StackupRow> rows)
    {
        var crossSection = CrossSectionContainer(document);
        if (crossSection == null) throw new InvalidDataException("\u5f53\u524d\u6280\u672f\u6587\u4ef6\u4e2d\u7f3a\u5c11\u53e0\u5c42\u622a\u9762\u6570\u636e\u3002");
        var modern = IsWholeFileFormat(document);
        var remove = new List<XmlNode>();
        foreach (XmlNode child in crossSection.ChildNodes)
        {
            var element = child as XmlElement;
            if (element != null && (element.LocalName == "layer" ||
                (element.LocalName == "object" && NamedAttribute(element, "Type").Length > 0)))
                remove.Add(child);
        }
        foreach (var child in remove) crossSection.RemoveChild(child);
        foreach (var row in rows)
            crossSection.AppendChild(LayerFromRow(document, row, modern, crossSection.NamespaceURI));
        if (modern) UpdateWholeFileStackupReferences(document, rows);
    }

    private static void UpdateWholeFileStackupReferences(XmlDocument document, IList<StackupRow> rows)
    {
        var stackupRoot = Child(ObjectsSection(document, "Stackup"), "root");
        if (stackupRoot != null)
        {
            XmlElement primary = null;
            foreach (var item in Children(stackupRoot, "object"))
                if (String.Equals(ObjectName(item), "PRIMARY", StringComparison.OrdinalIgnoreCase))
                {
                    primary = item;
                    break;
                }
            if (primary != null)
            {
                var remove = new List<XmlNode>();
                foreach (var member in Children(primary, "member"))
                    if (String.Equals(NamedAttribute(member, "Kind"), "Layer", StringComparison.OrdinalIgnoreCase))
                        remove.Add(member);
                foreach (var member in remove) primary.RemoveChild(member);
                for (var index = 0; index < rows.Count; index++)
                {
                    var member = document.CreateElement("member", primary.NamespaceURI);
                    member.SetAttribute("Kind", "Layer");
                    member.SetAttribute("Name", index.ToString(CultureInfo.InvariantCulture));
                    primary.AppendChild(member);
                }
            }
        }

        var children = CrossSectionContainer(document);
        if (children == null) return;
        var etchCount = 0;
        foreach (var row in rows)
        {
            var type = Value(row.Values, "Layer Type").ToUpperInvariant();
            if (type == "CONDUCTOR" || type == "PLANE") etchCount++;
        }
        children.SetAttribute("TopIndex", "0");
        children.SetAttribute("BottomIndex", Math.Max(0, etchCount - 1).ToString(CultureInfo.InvariantCulture));
    }

    private static void ResizePhysicalCSetArrays(
        XmlDocument document, IList<string> oldLayers, IList<string> newLayers)
    {
        if (oldLayers.Count == 0 || newLayers.Count == 0) return;
        var unchanged = oldLayers.Count == newLayers.Count;
        if (unchanged)
            for (var i = 0; i < oldLayers.Count; i++)
                if (!String.Equals(oldLayers[i], newLayers[i], StringComparison.OrdinalIgnoreCase))
                {
                    unchanged = false;
                    break;
                }
        if (unchanged) return;

        var oldIndexes = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < oldLayers.Count; i++) oldIndexes[oldLayers[i]] = i;
        foreach (var cset in PhysicalCSetElements(document))
        {
            var updates = new List<KeyValuePair<string, string>>();
            foreach (var attribute in Children(cset, "attribute"))
            {
                var name = AttributeName(attribute);
                if (!IsPhysicalLayerArrayAttribute(name)) continue;
                var values = AttributeValue(attribute).Split(',');
                if (values.Length != oldLayers.Count) continue;
                var resized = new string[newLayers.Count];
                for (var index = 0; index < newLayers.Count; index++)
                {
                    int oldIndex;
                    if (!oldIndexes.TryGetValue(newLayers[index], out oldIndex))
                    {
                        oldIndex = newLayers.Count == 1 ? 0 :
                            (int)Math.Round(index * (oldLayers.Count - 1.0) / (newLayers.Count - 1.0));
                    }
                    resized[index] = values[oldIndex].Trim();
                }
                updates.Add(new KeyValuePair<string, string>(name, String.Join(",", resized)));
            }
            foreach (var update in updates) SetLayerAttribute(document, cset, update.Key, update.Value);
        }
    }

    private static bool IsPhysicalLayerArrayAttribute(string name)
    {
        foreach (var supported in new[]
        {
            "MIN_LINE_WIDTH", "MIN_NECK_WIDTH", "MIN_BVIA_STAGGER", "MAX_BVIA_STAGGER",
            "TS_ALLOWED", "DIFFP_PRIMARY_GAP", "DIFFP_NECK_GAP", "MAX_LINE_WIDTH",
            "MAXIMUM_NECK_LENGTH", "PAD_PAD_DIRECT_CONNECT", "ALLOW_ON_ETCH_SUBCLASS",
            "DIFFP_COUPLED_PLUS", "DIFFP_COUPLED_MINUS", "DIFFP_MIN_SPACE"
        })
            if (String.Equals(name, supported, StringComparison.OrdinalIgnoreCase)) return true;
        return false;
    }

    private static void ReplacePhysicalCsets(XmlDocument document, IList<PhysicalCSetData> csets)
    {
        if (csets.Count == 0) return;
        var constraints = PhysicalCSetContainer(document);
        if (constraints == null) throw new InvalidDataException("\u5f53\u524d\u6280\u672f\u6587\u4ef6\u4e2d\u7f3a\u5c11 Physical CSet \u6570\u636e\u3002");

        var existing = new Dictionary<string, XmlElement>(StringComparer.OrdinalIgnoreCase);
        XmlElement template = null;
        XmlElement lastPhysical = null;
        foreach (var cset in PhysicalCSetElements(document))
        {
            var name = ObjectName(cset);
            existing[name] = cset;
            if (template == null || String.Equals(name, "DEFAULT", StringComparison.OrdinalIgnoreCase)) template = cset;
            lastPhysical = cset;
        }
        if (template == null)
            throw new InvalidDataException("\u5f53\u524d\u6280\u672f\u6587\u4ef6\u4e2d\u6ca1\u6709\u53ef\u4f5c\u4e3a\u6a21\u677f\u7684 Physical CSet\u3002");

        var etchLayers = GetEtchLayerNames(document);
        var layerIndexes = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < etchLayers.Count; i++) layerIndexes[etchLayers[i]] = i;
        var units = GetUnits(document);

        foreach (var data in csets)
        {
            XmlElement cset;
            if (!existing.TryGetValue(data.Name, out cset))
            {
                cset = (XmlElement)template.CloneNode(true);
                SetObjectName(document, cset, data.Name);
                if (lastPhysical == null) constraints.AppendChild(cset);
                else constraints.InsertAfter(cset, lastPhysical);
                lastPhysical = cset;
                existing[data.Name] = cset;
            }

            var widths = ReadConstraintArray(LayerAttribute(cset, "MIN_LINE_WIDTH"), etchLayers.Count);
            var gaps = ReadConstraintArray(LayerAttribute(cset, "DIFFP_PRIMARY_GAP"), etchLayers.Count);
            foreach (var layer in data.Layers)
            {
                int index;
                if (!layerIndexes.TryGetValue(layer.Key, out index))
                    throw new InvalidDataException("Physical CSet \u5bf9\u5e94\u7684\u5c42\u4e0d\u5b58\u5728\uff1a" + layer.Key);
                widths[index] = FormatDimension(FromMil(layer.Value.WidthMil, units));
                gaps[index] = layer.Value.GapMil > 0.0
                    ? FormatDimension(FromMil(layer.Value.GapMil, units)) : "0";
            }
            SetLayerAttribute(document, cset, "MIN_LINE_WIDTH", String.Join(",", widths.ToArray()));
            SetLayerAttribute(document, cset, "DIFFP_PRIMARY_GAP", String.Join(",", gaps.ToArray()));
        }
    }
}
