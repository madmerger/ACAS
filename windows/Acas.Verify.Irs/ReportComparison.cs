internal static class ReportComparison
{
    public static string? Difference(string expected, string actual)
    {
        const int sampleLimit = 20;
        var expectedLines = TrimBlankEdges(expected);
        var actualLines = TrimBlankEdges(actual);
        var sample = new List<int>(sampleLimit);
        int count = 0;
        for (int number = 1; !expectedLines.IsEmpty || !actualLines.IsEmpty; number++)
        {
            bool hasExpected = !expectedLines.IsEmpty, hasActual = !actualLines.IsEmpty;
            var expectedLine = ReadLine(ref expectedLines);
            var actualLine = ReadLine(ref actualLines);
            if (hasExpected == hasActual && expectedLine.SequenceEqual(actualLine)) continue;
            count++;
            if (sample.Count < sampleLimit) sample.Add(number);
        }

        if (count == 0) return null;
        string numbers = string.Join(",", sample);
        return count <= sampleLimit ? numbers : $"{numbers} ほか（全{count}行）";
    }

    private static ReadOnlySpan<char> TrimBlankEdges(ReadOnlySpan<char> body)
    {
        body = body.TrimEnd(" \r\n");
        while (!body.IsEmpty)
        {
            var rest = body;
            if (!ReadLine(ref rest).IsEmpty) break;
            body = rest;
        }
        return body;
    }

    private static ReadOnlySpan<char> ReadLine(ref ReadOnlySpan<char> body)
    {
        int end = body.IndexOf('\n');
        var line = end < 0 ? body : body[..end];
        body = end < 0 ? [] : body[(end + 1)..];
        return line.TrimEnd(" \r");
    }
}
