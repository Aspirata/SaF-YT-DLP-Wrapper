using System;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Text;

internal static class FakeGnuTar
{
    private static readonly DateTime UnixEpoch = new DateTime(1970, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    public static int Main(string[] args)
    {
        if (args.Length == 1 && args[0] == "--help")
        {
            Console.WriteLine("--mode=CHANGES");
            return 0;
        }

        if (args.Length < 7 || args[0] != "-czf" || args[2] != "-C" ||
            args[4] != "--transform=s/\\.exe$//" || args[5] != "--mode=a=rX,u+w")
        {
            Console.Error.WriteLine("Unexpected fake GNU tar arguments: " + string.Join(" ", args));
            return 2;
        }

        using (FileStream archive = File.Create(args[1]))
        using (GZipStream gzip = new GZipStream(archive, CompressionMode.Compress))
        {
            for (int index = 6; index < args.Length; index++)
            {
                string sourceName = args[index];
                string archiveName = sourceName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)
                    ? sourceName.Substring(0, sourceName.Length - 4)
                    : sourceName;
                string path = Path.Combine(args[3], sourceName);
                WriteEntry(gzip, path, archiveName, sourceName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ? 493 : 420);
            }

            gzip.Write(new byte[1024], 0, 1024);
        }

        return 0;
    }

    private static void WriteEntry(Stream archive, string path, string name, int mode)
    {
        byte[] content = File.ReadAllBytes(path);
        byte[] header = new byte[512];
        WriteText(header, 0, 100, name);
        WriteOctal(header, 100, 8, mode);
        WriteOctal(header, 108, 8, 0);
        WriteOctal(header, 116, 8, 0);
        WriteOctal(header, 124, 12, content.Length);
        long modified = (long)(File.GetLastWriteTimeUtc(path) - UnixEpoch).TotalSeconds;
        WriteOctal(header, 136, 12, modified);
        for (int index = 148; index < 156; index++) header[index] = 32;
        header[156] = (byte)'0';
        WriteText(header, 257, 6, "ustar");
        WriteText(header, 263, 2, "00");

        int checksum = 0;
        foreach (byte value in header) checksum += value;
        string checksumText = Convert.ToString(checksum, 8).PadLeft(6, '0');
        WriteText(header, 148, 6, checksumText);
        header[154] = 0;
        header[155] = 32;

        archive.Write(header, 0, header.Length);
        archive.Write(content, 0, content.Length);
        int padding = (512 - (content.Length % 512)) % 512;
        if (padding > 0) archive.Write(new byte[padding], 0, padding);
    }

    private static void WriteText(byte[] buffer, int offset, int length, string value)
    {
        byte[] encoded = Encoding.ASCII.GetBytes(value);
        Array.Copy(encoded, 0, buffer, offset, Math.Min(length, encoded.Length));
    }

    private static void WriteOctal(byte[] buffer, int offset, int length, long value)
    {
        string text = Convert.ToString(value, 8).PadLeft(length - 1, '0');
        WriteText(buffer, offset, length - 1, text);
        buffer[offset + length - 1] = 0;
    }
}
