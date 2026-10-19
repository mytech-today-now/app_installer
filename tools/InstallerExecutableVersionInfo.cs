using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class InstallerExecutableVersionInfo
{
    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumResourceTypesCallback(IntPtr module, IntPtr type, IntPtr parameter);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumResourceNamesCallback(IntPtr module, IntPtr type, IntPtr name, IntPtr parameter);

    [UnmanagedFunctionPointer(CallingConvention.Winapi)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private delegate bool EnumResourceLanguagesCallback(IntPtr module, IntPtr type, IntPtr name, ushort language, IntPtr parameter);

    private sealed class ResourceIdentifier
    {
        public bool IsInteger;
        public ushort Integer;
        public string Name;
    }

    private sealed class CabinetResource
    {
        public ResourceIdentifier Type;
        public ResourceIdentifier Name;
        public ushort Language;
        public byte[] Data;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr LoadLibraryEx(string fileName, IntPtr file, uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool FreeLibrary(IntPtr module);

    [DllImport("kernel32.dll", EntryPoint = "EnumResourceTypesW", SetLastError = true)]
    private static extern bool EnumResourceTypes(IntPtr module, EnumResourceTypesCallback callback, IntPtr parameter);

    [DllImport("kernel32.dll", EntryPoint = "EnumResourceNamesW", SetLastError = true)]
    private static extern bool EnumResourceNames(IntPtr module, IntPtr type, EnumResourceNamesCallback callback, IntPtr parameter);

    [DllImport("kernel32.dll", EntryPoint = "EnumResourceLanguagesW", SetLastError = true)]
    private static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, EnumResourceLanguagesCallback callback, IntPtr parameter);

    [DllImport("kernel32.dll", EntryPoint = "FindResourceExW", SetLastError = true)]
    private static extern IntPtr FindResourceEx(IntPtr module, IntPtr type, IntPtr name, ushort language);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint SizeofResource(IntPtr module, IntPtr resource);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LoadResource(IntPtr module, IntPtr resource);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LockResource(IntPtr resource);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr BeginUpdateResource(string fileName, bool deleteExistingResources);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool UpdateResource(IntPtr update, IntPtr type, IntPtr name, ushort language, byte[] data, uint size);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool EndUpdateResource(IntPtr update, bool discard);

    public static byte[] ReadCabinetResource(string path)
    {
        List<CabinetResource> resources = FindCabinetResources(path);
        if (resources.Count != 1)
        {
            throw new InvalidOperationException("The executable must contain exactly one IExpress cabinet resource.");
        }
        return resources[0].Data;
    }

    public static void ReplaceCabinetResource(string path, byte[] cabinet)
    {
        if (cabinet == null || cabinet.Length < 36 || Encoding.ASCII.GetString(cabinet, 0, 4) != "MSCF")
        {
            throw new ArgumentException("The replacement payload is not a valid cabinet header.", "cabinet");
        }

        List<CabinetResource> resources = FindCabinetResources(path);
        if (resources.Count != 1)
        {
            throw new InvalidOperationException("The executable must contain exactly one IExpress cabinet resource.");
        }

        CabinetResource target = resources[0];
        IntPtr type = AllocateResourceIdentifier(target.Type);
        IntPtr name = AllocateResourceIdentifier(target.Name);
        IntPtr update = IntPtr.Zero;
        bool resourceUpdated = false;
        try
        {
            update = BeginUpdateResource(path, false);
            if (update == IntPtr.Zero) ThrowLastWin32("Could not open the executable for cabinet resource update.");
            resourceUpdated = UpdateResource(update, type, name, target.Language, cabinet, (uint)cabinet.Length);
            if (!resourceUpdated) ThrowLastWin32("Could not replace the executable cabinet resource.");
        }
        finally
        {
            if (update != IntPtr.Zero && !EndUpdateResource(update, !resourceUpdated))
            {
                ThrowLastWin32("Could not finalize the executable cabinet resource update.");
            }
            FreeResourceIdentifier(target.Type, type);
            FreeResourceIdentifier(target.Name, name);
        }

        byte[] written = ReadCabinetResource(path);
        if (!BytesEqual(cabinet, written))
        {
            throw new InvalidOperationException("The embedded cabinet did not match the replacement payload after resource update.");
        }
    }

    private static List<CabinetResource> FindCabinetResources(string path)
    {
        const uint LoadLibraryAsDataFile = 0x00000002;
        List<CabinetResource> found = new List<CabinetResource>();
        IntPtr module = LoadLibraryEx(path, IntPtr.Zero, LoadLibraryAsDataFile);
        if (module == IntPtr.Zero) ThrowLastWin32("Could not open the executable resource table.");

        Exception callbackError = null;
        EnumResourceLanguagesCallback languageCallback = delegate(IntPtr currentModule, IntPtr type, IntPtr name, ushort language, IntPtr parameter)
        {
            try
            {
                IntPtr resource = FindResourceEx(currentModule, type, name, language);
                if (resource == IntPtr.Zero) ThrowLastWin32("Could not read an executable resource entry.");
                uint size = SizeofResource(currentModule, resource);
                if (size < 4) return true;
                IntPtr loaded = LoadResource(currentModule, resource);
                if (loaded == IntPtr.Zero) ThrowLastWin32("Could not load an executable resource entry.");
                IntPtr dataPointer = LockResource(loaded);
                if (dataPointer == IntPtr.Zero) ThrowLastWin32("Could not lock an executable resource entry.");
                byte[] signature = new byte[4];
                Marshal.Copy(dataPointer, signature, 0, signature.Length);
                if (Encoding.ASCII.GetString(signature) != "MSCF") return true;
                if (size > Int32.MaxValue) throw new InvalidOperationException("The executable cabinet resource is too large to inspect.");
                byte[] data = new byte[(int)size];
                Marshal.Copy(dataPointer, data, 0, data.Length);
                found.Add(new CabinetResource
                {
                    Type = ReadResourceIdentifier(type),
                    Name = ReadResourceIdentifier(name),
                    Language = language,
                    Data = data
                });
                return true;
            }
            catch (Exception exception)
            {
                callbackError = exception;
                return false;
            }
        };

        EnumResourceNamesCallback nameCallback = delegate(IntPtr currentModule, IntPtr type, IntPtr name, IntPtr parameter)
        {
            if (!EnumResourceLanguages(currentModule, type, name, languageCallback, IntPtr.Zero) && callbackError == null)
            {
                callbackError = LastWin32Exception("Could not enumerate executable resource languages.");
            }
            return callbackError == null;
        };

        EnumResourceTypesCallback typeCallback = delegate(IntPtr currentModule, IntPtr type, IntPtr parameter)
        {
            if (!EnumResourceNames(currentModule, type, nameCallback, IntPtr.Zero) && callbackError == null)
            {
                callbackError = LastWin32Exception("Could not enumerate executable resource names.");
            }
            return callbackError == null;
        };

        try
        {
            if (!EnumResourceTypes(module, typeCallback, IntPtr.Zero) && callbackError == null)
            {
                callbackError = LastWin32Exception("Could not enumerate executable resource types.");
            }
        }
        finally
        {
            FreeLibrary(module);
        }

        if (callbackError != null) throw callbackError;
        return found;
    }

    private static ResourceIdentifier ReadResourceIdentifier(IntPtr value)
    {
        long numericValue = value.ToInt64();
        if ((numericValue & ~0xFFFFL) == 0)
        {
            return new ResourceIdentifier { IsInteger = true, Integer = (ushort)numericValue };
        }
        return new ResourceIdentifier { IsInteger = false, Name = Marshal.PtrToStringUni(value) };
    }

    private static IntPtr AllocateResourceIdentifier(ResourceIdentifier identifier)
    {
        return identifier.IsInteger ? new IntPtr(identifier.Integer) : Marshal.StringToHGlobalUni(identifier.Name);
    }

    private static void FreeResourceIdentifier(ResourceIdentifier identifier, IntPtr value)
    {
        if (!identifier.IsInteger && value != IntPtr.Zero) Marshal.FreeHGlobal(value);
    }

    private static bool BytesEqual(byte[] left, byte[] right)
    {
        if (left == null || right == null || left.Length != right.Length) return false;
        for (int i = 0; i < left.Length; i++) if (left[i] != right[i]) return false;
        return true;
    }

    private static Exception LastWin32Exception(string message)
    {
        int error = Marshal.GetLastWin32Error();
        return new InvalidOperationException(message + " Win32 error: " + error + ".");
    }

    public static void Apply(string path, string productName, string companyName, string fileDescription, string originalFilename, string version, string comments, string copyright)
    {
        Version parsedVersion = new Version(version);
        int[] parts = new int[] { parsedVersion.Major, parsedVersion.Minor, parsedVersion.Build, parsedVersion.Revision };
        for (int i = 0; i < parts.Length; i++)
        {
            if (parts[i] < 0) parts[i] = 0;
            if (parts[i] > 65535) throw new ArgumentOutOfRangeException("version", "Version components must fit in Windows version resources.");
        }

        byte[] resource = BuildVersionResource(productName, companyName, fileDescription, originalFilename, version, comments, copyright, parts);
        IntPtr update = BeginUpdateResource(path, false);
        if (update == IntPtr.Zero) ThrowLastWin32("Could not open the executable for version resource update.");

        bool resourceUpdated = false;
        try
        {
            resourceUpdated = UpdateResource(update, new IntPtr(16), new IntPtr(1), 0x0409, resource, (uint)resource.Length);
            if (!resourceUpdated) ThrowLastWin32("Could not write the executable version resource.");
        }
        finally
        {
            if (!EndUpdateResource(update, !resourceUpdated))
            {
                ThrowLastWin32("Could not finalize the executable version resource update.");
            }
        }
    }

    private static byte[] BuildVersionResource(string productName, string companyName, string fileDescription, string originalFilename, string version, string comments, string copyright, int[] parts)
    {
        var fixedInfo = new List<byte>();
        AddDword(fixedInfo, 0xFEEF04BD);
        AddDword(fixedInfo, 0x00010000);
        AddDword(fixedInfo, ((uint)parts[0] << 16) | (uint)parts[1]);
        AddDword(fixedInfo, ((uint)parts[2] << 16) | (uint)parts[3]);
        AddDword(fixedInfo, ((uint)parts[0] << 16) | (uint)parts[1]);
        AddDword(fixedInfo, ((uint)parts[2] << 16) | (uint)parts[3]);
        AddDword(fixedInfo, 0x0000003F);
        AddDword(fixedInfo, 0x00000000);
        AddDword(fixedInfo, 0x00040004);
        AddDword(fixedInfo, 0x00000001);
        AddDword(fixedInfo, 0x00000000);
        AddDword(fixedInfo, 0x00000000);
        AddDword(fixedInfo, 0x00000000);

        var strings = new List<byte[]>();
        strings.Add(BuildStringBlock("CompanyName", companyName));
        strings.Add(BuildStringBlock("Comments", comments));
        strings.Add(BuildStringBlock("FileDescription", fileDescription));
        strings.Add(BuildStringBlock("FileVersion", version));
        strings.Add(BuildStringBlock("InternalName", originalFilename));
        strings.Add(BuildStringBlock("LegalCopyright", copyright));
        strings.Add(BuildStringBlock("OriginalFilename", originalFilename));
        strings.Add(BuildStringBlock("ProductName", productName));
        strings.Add(BuildStringBlock("ProductVersion", version));

        byte[] stringTable = BuildContainer("040904B0", strings, 0, 1);
        byte[] stringFileInfo = BuildContainer("StringFileInfo", new List<byte[]> { stringTable }, 0, 1);
        byte[] translation = new byte[] { 0x09, 0x04, 0xB0, 0x04 };
        byte[] translationBlock = BuildContainer("Translation", new List<byte[]>(), 4, 0, translation);
        byte[] varFileInfo = BuildContainer("VarFileInfo", new List<byte[]> { translationBlock }, 0, 1);

        var root = new List<byte>();
        AddWord(root, 0);
        AddWord(root, 52);
        AddWord(root, 0);
        AddUnicode(root, "VS_VERSION_INFO");
        PadToDword(root);
        root.AddRange(fixedInfo);
        PadToDword(root);
        root.AddRange(stringFileInfo);
        PadToDword(root);
        root.AddRange(varFileInfo);
        PadToDword(root);
        SetWord(root, 0, checked((ushort)root.Count));
        return root.ToArray();
    }

    private static byte[] BuildStringBlock(string key, string value)
    {
        return BuildContainer(key, new List<byte[]>(), checked((ushort)(value.Length + 1)), 1, Encoding.Unicode.GetBytes(value + "\0"));
    }

    private static byte[] BuildContainer(string key, List<byte[]> children, ushort valueLength, ushort type, byte[] value = null)
    {
        var block = new List<byte>();
        AddWord(block, 0);
        AddWord(block, valueLength);
        AddWord(block, type);
        AddUnicode(block, key);
        PadToDword(block);
        if (value != null)
        {
            block.AddRange(value);
            PadToDword(block);
        }
        foreach (byte[] child in children)
        {
            block.AddRange(child);
            PadToDword(block);
        }
        SetWord(block, 0, checked((ushort)block.Count));
        return block.ToArray();
    }

    private static void AddUnicode(List<byte> bytes, string value)
    {
        bytes.AddRange(Encoding.Unicode.GetBytes(value + "\0"));
    }

    private static void AddWord(List<byte> bytes, ushort value)
    {
        bytes.AddRange(BitConverter.GetBytes(value));
    }

    private static void AddDword(List<byte> bytes, uint value)
    {
        bytes.AddRange(BitConverter.GetBytes(value));
    }

    private static void PadToDword(List<byte> bytes)
    {
        while ((bytes.Count % 4) != 0) bytes.Add(0);
    }

    private static void SetWord(List<byte> bytes, int offset, ushort value)
    {
        byte[] word = BitConverter.GetBytes(value);
        bytes[offset] = word[0];
        bytes[offset + 1] = word[1];
    }

    private static void ThrowLastWin32(string message)
    {
        int error = Marshal.GetLastWin32Error();
        throw new InvalidOperationException(message + " Win32 error: " + error + ".");
    }
}
