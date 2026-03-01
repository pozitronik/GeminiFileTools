/// <summary>
///   DUnitX test runner for the GeminiFile library.
///   Console runner with NUnit XML output for CI compatibility.
/// </summary>
program GemViewTests;

{$APPTYPE CONSOLE}

{$STRONGLINKTYPES ON}

uses
  System.SysUtils,
  DUnitX.Loggers.Console,
  DUnitX.Loggers.Xml.NUnit,
  DUnitX.TestFramework,
  GeminiFile.Types in '..\src\GeminiFile.Types.pas',
  GeminiFile.Model in '..\src\GeminiFile.Model.pas',
  GeminiFile.Parser in '..\src\GeminiFile.Parser.pas',
  GeminiFile.Extractor in '..\src\GeminiFile.Extractor.pas',
  GeminiFile in '..\src\GeminiFile.pas',
  Tests.GeminiFile.Types in 'Tests.GeminiFile.Types.pas',
  Tests.GeminiFile.Resource in 'Tests.GeminiFile.Resource.pas',
  Tests.GeminiFile.Chunk in 'Tests.GeminiFile.Chunk.pas',
  Tests.GeminiFile.Parser in 'Tests.GeminiFile.Parser.pas',
  Tests.GeminiFile.Extractor in 'Tests.GeminiFile.Extractor.pas',
  Tests.GeminiFile.Integration in 'Tests.GeminiFile.Integration.pas';

var
  LRunner: ITestRunner;
  LResults: IRunResults;
  LLogger: ITestLogger;
  LNUnitLogger: ITestLogger;
begin
  try
    TDUnitX.CheckCommandLine;
    LRunner := TDUnitX.CreateRunner;
    LRunner.UseRTTI := True;
    LRunner.FailsOnNoAsserts := False;

    LLogger := TDUnitXConsoleLogger.Create(True);
    LRunner.AddLogger(LLogger);

    LNUnitLogger := TDUnitXXMLNUnitFileLogger.Create(TDUnitX.Options.XMLOutputFile);
    LRunner.AddLogger(LNUnitLogger);

    LResults := LRunner.Execute;
    if not LResults.AllPassed then
      ExitCode := 1;

    {$IFNDEF CI}
    if TDUnitX.Options.ExitBehavior = TDUnitXExitBehavior.Pause then
    begin
      Write('Press Enter to continue...');
      ReadLn;
    end;
    {$ENDIF}
  except
    on E: Exception do
    begin
      WriteLn('Fatal: ', E.ClassName, ': ', E.Message);
      ExitCode := 2;
    end;
  end;
end.
