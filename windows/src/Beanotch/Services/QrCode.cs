namespace Beanotch.Services;

// A QR code for a short text (an address), with nothing to install: byte mode, low error correction, versions 1 to 6
// (up to 134 bytes), mask 0. Follows the QR standard (ISO/IEC 18004); the layout steps mirror Project Nayuki's
// reference encoder.
public static class QrCode
{
    // Per version (1–6, error correction L): total codewords, error correction codewords per block, blocks.
    private static readonly (int Total, int Ecc, int Blocks)[] Versions =
        [(26, 7, 1), (44, 10, 1), (70, 15, 1), (100, 20, 1), (134, 26, 1), (172, 18, 2)];
    private static readonly int[][] Alignment = [[], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34]];

    // The modules, true for dark; null when the text is too long.
    public static bool[,]? Encode(string text)
    {
        var bytes = System.Text.Encoding.UTF8.GetBytes(text);
        var version = Array.FindIndex(Versions, v => 4 + 8 + bytes.Length * 8 <= (v.Total - v.Ecc * v.Blocks) * 8) + 1;
        if (version == 0) return null;
        var (total, ecc, blocks) = Versions[version - 1];
        var dataLength = total - ecc * blocks;

        // The data: byte mode, the length, the bytes, a terminator, then padding.
        var bits = new List<bool>();
        void Put(int value, int count) { for (var i = count - 1; i >= 0; i--) bits.Add(((value >> i) & 1) != 0); }
        Put(0b0100, 4);
        Put(bytes.Length, 8);
        foreach (var b in bytes) Put(b, 8);
        Put(0, Math.Min(4, dataLength * 8 - bits.Count));
        while (bits.Count % 8 != 0) bits.Add(false);
        var data = new List<byte>();
        for (var i = 0; i < bits.Count; i += 8) data.Add((byte)Enumerable.Range(0, 8).Aggregate(0, (v, j) => v << 1 | (bits[i + j] ? 1 : 0)));
        for (var pad = 0xEC; data.Count < dataLength; pad ^= 0xEC ^ 0x11) data.Add((byte)pad);

        // Split into blocks, add each one's error correction, and interleave.
        var per = dataLength / blocks;
        var divisor = Divisor(ecc);
        var dataBlocks = Enumerable.Range(0, blocks).Select(b => data.Skip(b * per).Take(per).ToArray()).ToArray();
        var eccBlocks = dataBlocks.Select(d => Remainder(d, divisor)).ToArray();
        var codewords = new List<byte>();
        for (var i = 0; i < per; i++) foreach (var d in dataBlocks) codewords.Add(d[i]);
        for (var i = 0; i < ecc; i++) foreach (var e in eccBlocks) codewords.Add(e[i]);

        var size = version * 4 + 17;
        var dark = new bool[size, size];
        var fixedModule = new bool[size, size];
        void Set(int x, int y, bool on) { dark[y, x] = on; fixedModule[y, x] = true; }

        for (var i = 0; i < size; i++) { Set(6, i, i % 2 == 0); Set(i, 6, i % 2 == 0); }
        foreach (var (cx, cy) in new[] { (3, 3), (size - 4, 3), (3, size - 4) })
            for (var dy = -4; dy <= 4; dy++)
                for (var dx = -4; dx <= 4; dx++)
                {
                    int x = cx + dx, y = cy + dy, d = Math.Max(Math.Abs(dx), Math.Abs(dy));
                    if (x >= 0 && x < size && y >= 0 && y < size) Set(x, y, d != 2 && d != 4);
                }
        var align = Alignment[version - 1];
        for (var i = 0; i < align.Length; i++)
            for (var j = 0; j < align.Length; j++)
            {
                if (i == 0 && j == 0 || i == 0 && j == align.Length - 1 || i == align.Length - 1 && j == 0) continue;
                for (var dy = -2; dy <= 2; dy++)
                    for (var dx = -2; dx <= 2; dx++) Set(align[i] + dx, align[j] + dy, Math.Max(Math.Abs(dx), Math.Abs(dy)) != 1);
            }
        Format(Set, size); // reserves the format areas before the data goes in

        var bit = 0;
        for (var right = size - 1; right >= 1; right -= 2)
        {
            if (right == 6) right = 5;
            for (var vert = 0; vert < size; vert++)
                for (var j = 0; j < 2; j++)
                {
                    var x = right - j;
                    var y = ((right + 1) & 2) == 0 ? size - 1 - vert : vert;
                    if (fixedModule[y, x] || bit >= codewords.Count * 8) continue;
                    dark[y, x] = ((codewords[bit >> 3] >> (7 - (bit & 7))) & 1) != 0;
                    bit++;
                }
        }
        for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
                if (!fixedModule[y, x] && (x + y) % 2 == 0) dark[y, x] = !dark[y, x]; // mask 0
        Format(Set, size);
        return dark;
    }

    // Error correction L (01) with mask 0, its BCH check, written twice beside the finder patterns.
    private static void Format(Action<int, int, bool> set, int size)
    {
        var data = 1 << 3;
        var rem = data;
        for (var i = 0; i < 10; i++) rem = (rem << 1) ^ ((rem >> 9) * 0x537);
        var bits = ((data << 10) | rem) ^ 0x5412;
        bool Bit(int i) => ((bits >> i) & 1) != 0;
        for (var i = 0; i <= 5; i++) set(8, i, Bit(i));
        set(8, 7, Bit(6));
        set(8, 8, Bit(7));
        set(7, 8, Bit(8));
        for (var i = 9; i < 15; i++) set(14 - i, 8, Bit(i));
        for (var i = 0; i < 8; i++) set(size - 1 - i, 8, Bit(i));
        for (var i = 8; i < 15; i++) set(8, size - 15 + i, Bit(i));
        set(8, size - 8, true);
    }

    private static byte Multiply(byte x, byte y)
    {
        var z = 0;
        for (var i = 7; i >= 0; i--)
        {
            z = (z << 1) ^ ((z >> 7) * 0x11D);
            z ^= ((y >> i) & 1) * x;
        }
        return (byte)z;
    }

    private static byte[] Divisor(int degree)
    {
        var result = new byte[degree];
        result[degree - 1] = 1;
        byte root = 1;
        for (var i = 0; i < degree; i++)
        {
            for (var j = 0; j < degree; j++)
            {
                result[j] = Multiply(result[j], root);
                if (j + 1 < degree) result[j] ^= result[j + 1];
            }
            root = Multiply(root, 2);
        }
        return result;
    }

    private static byte[] Remainder(byte[] data, byte[] divisor)
    {
        var result = new byte[divisor.Length];
        foreach (var b in data)
        {
            var factor = (byte)(b ^ result[0]);
            Array.Copy(result, 1, result, 0, result.Length - 1);
            result[^1] = 0;
            for (var i = 0; i < result.Length; i++) result[i] ^= Multiply(divisor[i], factor);
        }
        return result;
    }
}
