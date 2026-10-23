using System;
using System.Runtime.InteropServices;

namespace PhonoliteDistribution
{
    // Returns the native result so verification need not interpret localized messages.
    public static class SignatureVerifier
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct FileInfo
        {
            public uint Size;
            [MarshalAs(UnmanagedType.LPWStr)] public string Path;
            public IntPtr File;
            public IntPtr KnownSubject;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct TrustData
        {
            public uint Size;
            public IntPtr PolicyCallback;
            public IntPtr SipClient;
            public uint UiChoice;
            public uint RevocationChecks;
            public uint UnionChoice;
            public IntPtr File;
            public uint StateAction;
            public IntPtr StateData;
            public IntPtr UrlReference;
            public uint ProviderFlags;
            public uint UiContext;
            public IntPtr SignatureSettings;
        }

        [DllImport("wintrust.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern uint WinVerifyTrust(IntPtr window, ref Guid action, ref TrustData data);

        public static uint Verify(string path)
        {
            var info = new FileInfo { Size = (uint)Marshal.SizeOf(typeof(FileInfo)), Path = path };
            var pointer = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(FileInfo)));
            Marshal.StructureToPtr(info, pointer, false);
            var action = new Guid("00AAC56B-CD44-11D0-8CC2-00C04FC295EE");
            var data = new TrustData
            {
                Size = (uint)Marshal.SizeOf(typeof(TrustData)),
                UiChoice = 2,       // WTD_UI_NONE
                UnionChoice = 1,    // WTD_CHOICE_FILE
                File = pointer,
                StateAction = 1,    // WTD_STATEACTION_VERIFY
                ProviderFlags = 0x1010 // Cache-only retrieval, no online revocation checks.
            };
            try { return WinVerifyTrust(new IntPtr(-1), ref action, ref data); }
            finally
            {
                data.StateAction = 2; // WTD_STATEACTION_CLOSE
                WinVerifyTrust(new IntPtr(-1), ref action, ref data);
                Marshal.DestroyStructure(pointer, typeof(FileInfo));
                Marshal.FreeHGlobal(pointer);
            }
        }
    }
}
