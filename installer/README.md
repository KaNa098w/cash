# Leemon POS Windows Setup

## Build

1. Build the Windows app:

```powershell
flutter build windows --release
```

2. Build the updater:

```powershell
cd updater
dotnet publish .\Leemon.Updater.csproj -c Release
cd ..
```

3. Open `installer\leemon_setup.iss` in Inno Setup Compiler and build.

The setup writes this startup entry for Windows:

```text
HKLM\Software\Microsoft\Windows\CurrentVersion\Run
Leemon POS = "{app}\Leemon.exe"
```

The startup entry is removed automatically on uninstall.
