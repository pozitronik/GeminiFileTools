/// <summary>
///   WCX plugin SDK types, constants, and structures.
///   Based on the Total Commander WCX Plugin Interface specification.
/// </summary>
unit WcxApi;

interface

uses
	Winapi.Windows;

const
	// Open modes
	PK_OM_LIST = 0;
	PK_OM_EXTRACT = 1;

	// Operations
	PK_SKIP = 0;
	PK_TEST = 1;
	PK_EXTRACT = 2;

	// Error codes
	E_END_ARCHIVE = 10;
	E_NO_MEMORY = 11;
	E_BAD_DATA = 12;
	E_BAD_ARCHIVE = 13;
	E_UNKNOWN_FORMAT = 14;
	E_EOPEN = 15;
	E_ECREATE = 16;
	E_ECLOSE = 17;
	E_EREAD = 18;
	E_EWRITE = 19;
	E_SMALL_BUF = 20;
	E_EABORTED = 21;
	E_NO_FILES = 22;
	E_TOO_MANY_FILES = 23;
	E_NOT_SUPPORTED = 24;

	// Capabilities
	PK_CAPS_NEW = 1;
	PK_CAPS_MODIFY = 2;
	PK_CAPS_MULTIPLE = 4;
	PK_CAPS_DELETE = 8;
	PK_CAPS_OPTIONS = 16;
	PK_CAPS_MEMPACK = 32;
	PK_CAPS_BY_CONTENT = 64;
	PK_CAPS_SEARCHTEXT = 128;
	PK_CAPS_HIDE = 256;
	PK_CAPS_ENCRYPT = 512;

	// Background flags
	BACKGROUND_UNPACK = 1;
	BACKGROUND_PACK = 2;

type
	// ANSI open archive structure
	TOpenArchiveData = record
		ArcName: PAnsiChar;
		OpenMode: Integer;
		OpenResult: Integer;
		CmtBuf: PAnsiChar;
		CmtBufSize: Integer;
		CmtSize: Integer;
		CmtState: Integer;
	end;

	POpenArchiveData = ^TOpenArchiveData;

	// Unicode open archive structure
	TOpenArchiveDataW = record
		ArcName: PWideChar;
		OpenMode: Integer;
		OpenResult: Integer;
		CmtBuf: PWideChar;
		CmtBufSize: Integer;
		CmtSize: Integer;
		CmtState: Integer;
	end;

	POpenArchiveDataW = ^TOpenArchiveDataW;

	// ANSI header (basic)
	THeaderData = record
		ArcName: array [0 .. 259] of AnsiChar;
		FileName: array [0 .. 259] of AnsiChar;
		Flags: Integer;
		PackSize: Integer;
		UnpSize: Integer;
		HostOS: Integer;
		FileCRC: Integer;
		FileTime: Integer;
		UnpVer: Integer;
		Method: Integer;
		FileAttr: Integer;
		CmtBuf: PAnsiChar;
		CmtBufSize: Integer;
		CmtSize: Integer;
		CmtState: Integer;
	end;

	PHeaderData = ^THeaderData;

	// ANSI header (extended)
	THeaderDataEx = record
		ArcName: array [0 .. 1023] of AnsiChar;
		FileName: array [0 .. 1023] of AnsiChar;
		Flags: Integer;
		PackSize: Cardinal;
		PackSizeHigh: Cardinal;
		UnpSize: Cardinal;
		UnpSizeHigh: Cardinal;
		HostOS: Integer;
		FileCRC: Integer;
		FileTime: Integer;
		UnpVer: Integer;
		Method: Integer;
		FileAttr: Integer;
		CmtBuf: PAnsiChar;
		CmtBufSize: Integer;
		CmtSize: Integer;
		CmtState: Integer;
		Reserved: array [0 .. 1023] of AnsiChar;
	end;

	PHeaderDataEx = ^THeaderDataEx;

	// Unicode header (extended)
	THeaderDataExW = record
		ArcName: array [0 .. 1023] of WideChar;
		FileName: array [0 .. 1023] of WideChar;
		Flags: Integer;
		PackSize: Cardinal;
		PackSizeHigh: Cardinal;
		UnpSize: Cardinal;
		UnpSizeHigh: Cardinal;
		HostOS: Integer;
		FileCRC: Integer;
		FileTime: Integer;
		UnpVer: Integer;
		Method: Integer;
		FileAttr: Integer;
		CmtBuf: PAnsiChar;
		CmtBufSize: Integer;
		CmtSize: Integer;
		CmtState: Integer;
		Reserved: array [0 .. 1023] of AnsiChar;
	end;

	PHeaderDataExW = ^THeaderDataExW;

	// Callbacks
	TProcessDataProc = function(FileName: PAnsiChar; Size: Integer): Integer; stdcall;
	TProcessDataProcW = function(FileName: PWideChar; Size: Integer): Integer; stdcall;
	TChangeVolProc = function(ArcName: PAnsiChar; Mode: Integer): Integer; stdcall;
	TChangeVolProcW = function(ArcName: PWideChar; Mode: Integer): Integer; stdcall;

	// Default params
	TPackDefaultParamStruct = record
		Size: Integer;
		PluginInterfaceVersionLow: Integer;
		PluginInterfaceVersionHi: Integer;
		DefaultIniName: array [0 .. 259] of AnsiChar;
	end;

implementation

end.
