# SourceMod AutoDemo Recording System
Server plugin for AutoDemo system

## Requirements
- **[SourceMod 1.9](https://sm.alliedmods.net/)** or higher
- **[SourceTV Manager](https://forums.alliedmods.net/showthread.php?t=280402)**
- Nice hands

## Installing
- Download [the repository content fully](https://github.com/CrazyHackGUT/sm-autodemo/archive/master.zip) or [latest release archive](https://github.com/CrazyHackGUT/sm-autodemo/releases).
- Unpack archive. <br />
  if you downloaded repository content fully, you need build plugin. Go to [Building](#building) for more information.
- Upload files on game server.
- Enable SourceTV on server. For more information, read section [SourceTV enabling](#sourcetv-enabling).
- Restart the map or server.

## Building
For compiling sourcepawn source file (*.sp*), you need SourcePawn Compiler on your PC. You can download him from [here](https://sm.alliedmods.net/downloads.php?branch=stable).

**Note**: You should download archive for your OS. All plugins, compiled on Windows, can run on server with Linux, and vice versa.

If you use Windows, you must select the source file (*.sp*) and transfer it to **spcomp.exe**. You will compile the source and you will receive a plugin (*.smx*).

Else you use Linux, then you need to register **./spcomp file.sp** and you will compile the file.

**P.S.**: In both cases, the plugin is compiled into the source folder. But in the case of Linux, for everything to work, you must be in the folder with the compiler. Also if you use SM 1.10+, then it's better to use `spcomp64`.

## SourceTV Enabling
To enable SourceTV, you need to register the following in **server.cfg**:
```
// SourceTV options
tv_enable 1
tv_autorecord 0
tv_maxclients 0
tv_name "AutoDemo"
tv_port 27020
```
