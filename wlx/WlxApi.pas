/// <summary>
///   WLX plugin SDK types, constants, and structures.
///   Based on the Total Commander Lister Plugin Interface specification.
/// </summary>
unit WlxApi;

interface

uses
	Winapi.Windows;

const
	// Return codes
	LISTPLUGIN_OK = 0;
	LISTPLUGIN_ERROR = 1;

	// Command constants for ListSendCommand
	lc_copy = 1;
	lc_newparams = 2;
	lc_selectall = 3;
	lc_setpercent = 4;

	// Show/parameter flags for ListSendCommand (lc_newparams)
	lcp_wraptext = 1;
	lcp_fittowindow = 2;
	lcp_ansi = 4;
	lcp_ascii = 8;
	lcp_variable = 12;
	lcp_forceshow = 16;
	lcp_fitlargeronly = 32;
	lcp_center = 64;
	lcp_darkmode = 128;
	lcp_darkmodenative = 256;

	// Search flags for ListSearchText
	lcs_findfirst = 1;
	lcs_matchcase = 2;
	lcs_wholewords = 4;
	lcs_backwards = 8;

	// PostMessage item types
	itm_percent = $FFFE;
	itm_fontstyle = $FFFD;
	itm_wrap = $FFFC;
	itm_fit = $FFFB;
	itm_next = $FFFA;
	itm_center = $FFF9;

type
	TListDefaultParamStruct = record
		Size: Integer;
		PluginInterfaceVersionLow: Integer;
		PluginInterfaceVersionHi: Integer;
		DefaultIniName: array [0 .. MAX_PATH - 1] of AnsiChar;
	end;

	PListDefaultParamStruct = ^TListDefaultParamStruct;

implementation

end.
