using System;
using System.IO;
using System.Linq;

internal static class FakeFfmpeg
{
    private static bool HasArgument(string[] args, string value)
    {
        return args.Any(argument => string.Equals(argument, value, StringComparison.OrdinalIgnoreCase));
    }

    private static string ValueAfter(string[] args, string option)
    {
        for (var index = 0; index < args.Length - 1; index++)
        {
            if (string.Equals(args[index], option, StringComparison.OrdinalIgnoreCase))
            {
                return args[index + 1];
            }
        }
        return string.Empty;
    }

    public static int Main(string[] args)
    {
        var executable = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]);
        var logPath = Environment.GetEnvironmentVariable("SAF_FFMPEG_LOG");
        if (!string.IsNullOrEmpty(logPath))
        {
            using (var writer = File.AppendText(logPath))
            {
                writer.WriteLine(string.Equals(executable, "ffprobe", StringComparison.OrdinalIgnoreCase) ? "FFPROBE" : "FFMPEG");
                foreach (var argument in args)
                {
                    writer.WriteLine("ARG=[{0}]", argument);
                }
            }
        }

        if (string.Equals(executable, "ffprobe", StringComparison.OrdinalIgnoreCase))
        {
            var entries = ValueAfter(args, "-show_entries");
            if (entries.IndexOf("stream=index,codec_type,codec_name,pix_fmt,height,bit_rate:format=duration", StringComparison.OrdinalIgnoreCase) >= 0
                && string.Equals(ValueAfter(args, "-of"), "json", StringComparison.OrdinalIgnoreCase))
            {
                var audioCodecs = (Environment.GetEnvironmentVariable("SAF_FAKE_ACTUAL_AUDIO_CODECS")
                    ?? Environment.GetEnvironmentVariable("SAF_FAKE_ACTUAL_AUDIO_CODEC")
                    ?? "opus").Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
                var audioStreams = string.Join(",", audioCodecs.Select((codec, index) => "{\"index\":" + (index + 1)
                    + ",\"codec_type\":\"audio\",\"codec_name\":\"" + codec.Trim() + "\"}").ToArray());
                Console.WriteLine("{\"streams\":[{\"index\":0,\"codec_type\":\"video\",\"codec_name\":\""
                    + (Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_CODEC") ?? "vp9")
                    + "\",\"pix_fmt\":\"" + (Environment.GetEnvironmentVariable("SAF_FAKE_PIX_FMT") ?? "yuv420p")
                    + "\",\"height\":" + (Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_HEIGHT") ?? "1080")
                    + ",\"bit_rate\":\"" + (Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_BITRATE") ?? "8000000")
                    + "\"}" + (audioStreams.Length > 0 ? "," + audioStreams : string.Empty)
                    + "],\"format\":{\"duration\":\"" + (Environment.GetEnvironmentVariable("SAF_FAKE_DURATION") ?? "10") + "\"}}");
            }
            else if (entries.IndexOf("pix_fmt", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Console.WriteLine(Environment.GetEnvironmentVariable("SAF_FAKE_PIX_FMT") ?? "yuv420p");
            }
            else if (entries.IndexOf("codec_name", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                var codecs = Environment.GetEnvironmentVariable("SAF_FAKE_ACTUAL_AUDIO_CODECS")
                    ?? Environment.GetEnvironmentVariable("SAF_FAKE_ACTUAL_AUDIO_CODEC")
                    ?? "opus";
                foreach (var codec in codecs.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    Console.WriteLine(codec.Trim());
                }
            }
            else if (entries.IndexOf("bit_rate", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Console.WriteLine(Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_BITRATE") ?? "8000000");
            }
            else if (entries.IndexOf("height", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Console.WriteLine(Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_HEIGHT") ?? "1080");
            }
            else if (entries.IndexOf("duration", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                Console.WriteLine(Environment.GetEnvironmentVariable("SAF_FAKE_DURATION") ?? "10");
            }
            else if (entries.IndexOf("packet=size", StringComparison.OrdinalIgnoreCase) >= 0)
            {
                var sizes = Environment.GetEnvironmentVariable("SAF_FAKE_PACKET_SIZES") ?? "5000000,5000000";
                foreach (var size in sizes.Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries))
                {
                    Console.WriteLine(size.Trim());
                }
            }
            return 0;
        }

        var encoder = ValueAfter(args, "-c:v");
        if (HasArgument(args, "lavfi"))
        {
            var supported = (Environment.GetEnvironmentVariable("SAF_FAKE_HARDWARE_ENCODERS") ?? string.Empty)
                .Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            return supported.Any(item => string.Equals(item.Trim(), encoder, StringComparison.OrdinalIgnoreCase)) ? 0 : 1;
        }

        var failingEncoder = Environment.GetEnvironmentVariable("SAF_FAKE_FAIL_ENCODER");
        if (!string.IsNullOrEmpty(failingEncoder) && string.Equals(failingEncoder, encoder, StringComparison.OrdinalIgnoreCase))
        {
            int exitCode;
            return int.TryParse(Environment.GetEnvironmentVariable("SAF_FAKE_FAIL_EXIT"), out exitCode) ? exitCode : 1;
        }
        var failingInput = Environment.GetEnvironmentVariable("SAF_FAKE_FAIL_INPUT_CONTAINS");
        var input = ValueAfter(args, "-i");
        if (!string.IsNullOrEmpty(failingInput) && input.IndexOf(failingInput, StringComparison.OrdinalIgnoreCase) >= 0)
        {
            return 1;
        }

        if (HasArgument(args, "null"))
        {
            return 0;
        }

        if (args.Length > 0)
        {
            File.WriteAllText(args[args.Length - 1], "encoded media");
        }
        return 0;
    }
}
