using System;
using System.IO;

internal static class FakeYtdlp
{
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

    private static int ReadExitCode(string name)
    {
        int value;
        return int.TryParse(Environment.GetEnvironmentVariable(name), out value) ? value : 0;
    }

    private static bool HasArgument(string[] args, string option)
    {
        foreach (var argument in args)
        {
            if (string.Equals(argument, option, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    public static int Main(string[] args)
    {
        if (args.Length > 0 && args[0] == "--update-to")
        {
            return ReadExitCode("SAF_FAKE_UPDATE_EXIT");
        }
        if (args.Length > 0 && args[0] == "--version")
        {
            return ReadExitCode("SAF_FAKE_VERSION_EXIT");
        }

        var logPath = Environment.GetEnvironmentVariable("SAF_ARGUMENT_LOG");
        if (!string.IsNullOrEmpty(logPath))
        {
            using (var writer = File.AppendText(logPath))
            {
                writer.WriteLine("CALL");
                foreach (var argument in args)
                {
                    writer.WriteLine("ARG=[{0}]", argument);
                }
            }
        }

        if (HasArgument(args, "--simulate"))
        {
            var expectedCookieSource = Environment.GetEnvironmentVariable("SAF_FAKE_COOKIE_SUCCESS");
            var actualCookieSource = ValueAfter(args, "--cookies-from-browser");
            if (string.IsNullOrEmpty(expectedCookieSource))
            {
                return 0;
            }
            if (string.Equals(expectedCookieSource, "ZEN", StringComparison.OrdinalIgnoreCase))
            {
                return actualCookieSource.StartsWith("firefox:", StringComparison.OrdinalIgnoreCase)
                    && actualCookieSource.IndexOf(@"\zen\Profiles", StringComparison.OrdinalIgnoreCase) >= 0 ? 0 : 1;
            }
            if (string.Equals(expectedCookieSource, "COMET", StringComparison.OrdinalIgnoreCase))
            {
                return actualCookieSource.StartsWith("chrome:", StringComparison.OrdinalIgnoreCase)
                    && actualCookieSource.IndexOf(@"\Perplexity\Comet\User Data\Default", StringComparison.OrdinalIgnoreCase) >= 0 ? 0 : 1;
            }
            if (string.Equals(expectedCookieSource, "COMET_PROFILE2", StringComparison.OrdinalIgnoreCase))
            {
                return actualCookieSource.StartsWith("chrome:", StringComparison.OrdinalIgnoreCase)
                    && actualCookieSource.EndsWith(@"\Perplexity\Comet\User Data\Profile 2", StringComparison.OrdinalIgnoreCase) ? 0 : 1;
            }
            return string.Equals(expectedCookieSource, actualCookieSource, StringComparison.OrdinalIgnoreCase) ? 0 : 1;
        }

        var failedCookieSource = Environment.GetEnvironmentVariable("SAF_FAKE_DOWNLOAD_FAIL_COOKIE");
        var failedCookieItem = Environment.GetEnvironmentVariable("SAF_FAKE_DOWNLOAD_FAIL_COOKIE_ITEM");
        var actualPlaylistItem = ValueAfter(args, "--playlist-items");
        if (!string.IsNullOrEmpty(failedCookieSource)
            && string.Equals(failedCookieSource, ValueAfter(args, "--cookies-from-browser"), StringComparison.OrdinalIgnoreCase)
            && (string.IsNullOrEmpty(failedCookieItem) || string.Equals(failedCookieItem, actualPlaylistItem, StringComparison.OrdinalIgnoreCase)))
        {
            return 1;
        }

        if (HasArgument(args, "--dump-single-json"))
        {
            Console.Write(Environment.GetEnvironmentVariable("SAF_FAKE_METADATA_JSON") ?? "{}");
            return 0;
        }

        var mediaPath = Environment.GetEnvironmentVariable("SAF_FAKE_MEDIA_PATH");
        var mediaName = Environment.GetEnvironmentVariable("SAF_FAKE_MEDIA_NAME");
        var outputDirectory = ValueAfter(args, "-P");
        if (!string.IsNullOrEmpty(mediaName) && !string.IsNullOrEmpty(outputDirectory))
        {
            mediaPath = Path.Combine(outputDirectory, mediaName);
        }
        if (!string.IsNullOrEmpty(mediaPath))
        {
            Directory.CreateDirectory(Path.GetDirectoryName(mediaPath));
            File.WriteAllText(mediaPath, args.Length > 0 ? args[args.Length - 1] : "fake media");
            for (var index = 0; index < args.Length - 2; index++)
            {
                if (args[index] != "--print-to-file")
                {
                    continue;
                }

                var videoCodec = Environment.GetEnvironmentVariable("SAF_FAKE_VIDEO_CODEC") ?? "vp9";
                var audioCodec = Environment.GetEnvironmentVariable("SAF_FAKE_AUDIO_CODEC") ?? "opus";
                var printParts = args[index + 1].Split('\t');
                var extraFields = printParts.Length > 3 ? "\t" + printParts[3] : string.Empty;
                File.AppendAllText(args[index + 2], string.Format("{0}\t{1}\t{2}{3}{4}", mediaPath, videoCodec, audioCodec, extraFields, Environment.NewLine));
                var secondMediaPath = Environment.GetEnvironmentVariable("SAF_FAKE_SECOND_MEDIA_PATH");
                var secondMediaName = Environment.GetEnvironmentVariable("SAF_FAKE_SECOND_MEDIA_NAME");
                if (!string.IsNullOrEmpty(secondMediaName) && !string.IsNullOrEmpty(outputDirectory))
                {
                    secondMediaPath = Path.Combine(outputDirectory, secondMediaName);
                }
                if (!string.IsNullOrEmpty(secondMediaPath))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(secondMediaPath));
                    File.WriteAllText(secondMediaPath, "fake media");
                    var secondVideoCodec = Environment.GetEnvironmentVariable("SAF_FAKE_SECOND_VIDEO_CODEC") ?? videoCodec;
                    var secondAudioCodec = Environment.GetEnvironmentVariable("SAF_FAKE_SECOND_AUDIO_CODEC") ?? audioCodec;
                    File.AppendAllText(args[index + 2], string.Format("{0}\t{1}\t{2}{3}{4}", secondMediaPath, secondVideoCodec, secondAudioCodec, extraFields, Environment.NewLine));
                }
                break;
            }
        }

        return ReadExitCode("SAF_FAKE_DOWNLOAD_EXIT");
    }
}
