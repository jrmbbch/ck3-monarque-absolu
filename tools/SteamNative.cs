// Minimal native ABI bridge for PowerShell. No publisher logic or credentials here.
// The SDK library is supplied by CK3; .NET loads its exports dynamically.
using System;
using System.Runtime.InteropServices;
namespace MonarqueAbsolu {
    [StructLayout(LayoutKind.Sequential)] public struct CallbackMessage {
        public int User, Callback; public IntPtr Data; public int Size;
    }
    [StructLayout(LayoutKind.Sequential)] public struct CallCompleted {
        public ulong Handle; public int Callback; public uint Size;
    }
    public sealed class SteamApi : IDisposable {
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        public delegate bool InitFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void VoidFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate IntPtr PointerFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate int PipeFn();
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void FrameFn(int pipe);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        public delegate bool NextFn(int pipe, ref CallbackMessage message);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate ulong StartFn(IntPtr ugc, uint appId, ulong itemId);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        public delegate bool SetFn(IntPtr ugc, ulong handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string value);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate ulong SubmitFn(IntPtr ugc, ulong handle, [MarshalAs(UnmanagedType.LPUTF8Str)] string notes);
        [UnmanagedFunctionPointer(CallingConvention.Cdecl)] [return: MarshalAs(UnmanagedType.I1)]
        public delegate bool ResultFn(int pipe, ulong call, IntPtr output, int size, int callback, [MarshalAs(UnmanagedType.I1)] out bool failed);
        // On macOS, managed environment changes are not visible to native getenv().
        [DllImport("libSystem.B.dylib", EntryPoint="getenv")] private static extern IntPtr GetEnv(string name);
        [DllImport("libSystem.B.dylib", EntryPoint="setenv")] private static extern int SetEnv(string name, string value, int overwrite);
        [DllImport("libSystem.B.dylib", EntryPoint="unsetenv")] private static extern int UnsetEnv(string name);
        private string oldApp, oldGame;
        private bool environmentSet;
        private IntPtr library;
        private VoidFn shutdown;
        private bool initialized;
        public readonly IntPtr Ugc;
        public readonly int Pipe;
        public readonly StartFn Start;
        public readonly SubmitFn Submit;
        public readonly FrameFn Frame, Free;
        public readonly NextFn Next;
        public readonly ResultFn Result;
        public readonly SetFn Title, Description, Content, Preview;
        private T Bind<T>(string name) where T : Delegate => Marshal.GetDelegateForFunctionPointer<T>(NativeLibrary.GetExport(library, name));
        public SteamApi(string path) {
            library = NativeLibrary.Load(path);
            try {
                if (OperatingSystem.IsMacOS()) {
                    oldApp = Marshal.PtrToStringUTF8(GetEnv("SteamAppId"));
                    oldGame = Marshal.PtrToStringUTF8(GetEnv("SteamGameId"));
                    environmentSet = true;
                    if (SetEnv("SteamAppId", "1158310", 1) != 0 || SetEnv("SteamGameId", "1158310", 1) != 0)
                        throw new InvalidOperationException("Unable to set native Steam application environment");
                }
                shutdown = Bind<VoidFn>("SteamAPI_Shutdown");
                if (!Bind<InitFn>("SteamAPI_Init")()) throw new InvalidOperationException("Steam initialization failed; open Steam and sign in to the owner account");
                initialized = true;
                Ugc = Bind<PointerFn>("SteamAPI_SteamUGC_v016")();
                if (Ugc == IntPtr.Zero) throw new InvalidOperationException("Required Steamworks interface unavailable");
                Start = Bind<StartFn>("SteamAPI_ISteamUGC_StartItemUpdate");
                Submit = Bind<SubmitFn>("SteamAPI_ISteamUGC_SubmitItemUpdate");
                Title = Bind<SetFn>("SteamAPI_ISteamUGC_SetItemTitle");
                Description = Bind<SetFn>("SteamAPI_ISteamUGC_SetItemDescription");
                Content = Bind<SetFn>("SteamAPI_ISteamUGC_SetItemContent");
                Preview = Bind<SetFn>("SteamAPI_ISteamUGC_SetItemPreview");
                Bind<VoidFn>("SteamAPI_ManualDispatch_Init")();
                Pipe = Bind<PipeFn>("SteamAPI_GetHSteamPipe")();
                Frame = Bind<FrameFn>("SteamAPI_ManualDispatch_RunFrame");
                Next = Bind<NextFn>("SteamAPI_ManualDispatch_GetNextCallback");
                Free = Bind<FrameFn>("SteamAPI_ManualDispatch_FreeLastCallback");
                Result = Bind<ResultFn>("SteamAPI_ManualDispatch_GetAPICallResult");
            } catch { Dispose(); throw; }
        }
        public void Dispose() {
            if (initialized) { shutdown(); initialized = false; }
            if (environmentSet) {
                if (oldApp == null) UnsetEnv("SteamAppId"); else SetEnv("SteamAppId", oldApp, 1);
                if (oldGame == null) UnsetEnv("SteamGameId"); else SetEnv("SteamGameId", oldGame, 1);
                environmentSet = false;
            }
            if (library != IntPtr.Zero) { NativeLibrary.Free(library); library = IntPtr.Zero; }
        }
    }
}
