#define AppName "Moka Skill"
#define AppVersion "1.0.0"
#define AppDisplayVersion "v1.0"
#define AppPublisher "Moka Skill"

[Setup]
AppId={{8D96E095-4314-4B59-ABF4-EA8688747F86}
AppName={#AppName}
AppVersion={#AppDisplayVersion}
AppVerName={#AppName} {#AppDisplayVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Programs\Moka Skill
DefaultGroupName=Moka Skill
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=..\dist
OutputBaseFilename=MokaSkill_Setup_{#AppDisplayVersion}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=110
SetupLogging=yes
Uninstallable=yes
UninstallDisplayName={#AppName} {#AppDisplayVersion}
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} installer
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
CloseApplications=no
UsePreviousAppDir=yes

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "..\src\moka_loader.il"; DestDir: "{app}"; DestName: "moka_loader.il"; Flags: ignoreversion; Check: UseChineseMenu
Source: "..\src\moka_loader_en.il"; DestDir: "{app}"; DestName: "moka_loader.il"; Flags: ignoreversion; Check: UseEnglishMenu
Source: "..\src\moka_core.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\align_tools.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\spread_between_clines.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\pin_swap.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\dp_antipad.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\moka_copper_corner.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\stackup_impedance.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\allegro_cleanup.il"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\src\pcb-symbols\mooretronics_symbols.il"; DestDir: "{app}\mooretronics-symbols"; Flags: ignoreversion
Source: "..\src\pcb-symbols\mooretronics_glyphs.il"; DestDir: "{app}\mooretronics-symbols"; Flags: ignoreversion
Source: "..\src\pcb-symbols\icons\*.bmp"; DestDir: "{app}\mooretronics-symbols\icons"; Flags: ignoreversion
Source: "..\src\runtime\MokaStackupBridge.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\MokaSkillConfig.exe"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\卸载 Moka Skill"; Filename: "{uninstallexe}"; Languages: chinesesimp
Name: "{group}\Uninstall Moka Skill"; Filename: "{uninstallexe}"; Languages: english

[Run]
Filename: "{app}\MokaSkillConfig.exe"; Parameters: "install ""{app}"" ""{code:GetSpbHome}"""; StatusMsg: "正在配置 Allegro 用户环境..."; Flags: runhidden waituntilterminated; Languages: chinesesimp
Filename: "{app}\MokaSkillConfig.exe"; Parameters: "install ""{app}"" ""{code:GetSpbHome}"""; StatusMsg: "Configuring the Allegro user environment..."; Flags: runhidden waituntilterminated; Languages: english

[UninstallRun]
Filename: "{app}\MokaSkillConfig.exe"; Parameters: "uninstall ""{app}"""; RunOnceId: "MokaSkillConfigCleanup"; Flags: runhidden waituntilterminated

[UninstallDelete]
Type: files; Name: "{app}\moka.env"
Type: files; Name: "{app}\install-state.txt"
Type: dirifempty; Name: "{app}\mooretronics-symbols\icons"
Type: dirifempty; Name: "{app}\mooretronics-symbols"
Type: dirifempty; Name: "{app}"

[Code]
var
  SpbHomePage: TInputDirWizardPage;
  MenuLanguagePage: TInputOptionWizardPage;

function DefaultSpbHome: String;
begin
  Result := ExpandConstant('{param:SPBHOME|}');
  if Result = '' then
    Result := GetEnv('HOME');
  if Result = '' then
    Result := 'D:\Cadence\SPB_Data';
end;

procedure InitializeWizard;
begin
  SpbHomePage := CreateInputDirPage(
    wpSelectDir,
    CustomMessage('SpbHomeTitle'),
    CustomMessage('SpbHomeDescription'),
    CustomMessage('SpbHomeSubCaption'),
    False,
    '');
  SpbHomePage.Add('');
  SpbHomePage.Values[0] := DefaultSpbHome;

  MenuLanguagePage := CreateInputOptionPage(
    SpbHomePage.ID,
    CustomMessage('MenuLanguageTitle'),
    CustomMessage('MenuLanguageDescription'),
    CustomMessage('MenuLanguageSubCaption'),
    True,
    False);
  MenuLanguagePage.Add(CustomMessage('ChineseMenu'));
  MenuLanguagePage.Add('English');
  if CompareText(ExpandConstant('{param:MENULANG|chinese}'), 'english') = 0 then
    MenuLanguagePage.SelectedValueIndex := 1
  else
    MenuLanguagePage.SelectedValueIndex := 0;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  Result := True;
  if (CurPageID = SpbHomePage.ID) and (Trim(SpbHomePage.Values[0]) = '') then
  begin
    MsgBox(CustomMessage('SpbHomeRequired'), mbError, MB_OK);
    Result := False;
  end;
end;

function GetSpbHome(Param: String): String;
begin
  Result := SpbHomePage.Values[0];
end;

function UseChineseMenu: Boolean;
begin
  Result := MenuLanguagePage.SelectedValueIndex = 0;
end;

function UseEnglishMenu: Boolean;
begin
  Result := not UseChineseMenu;
end;

[CustomMessages]
chinesesimp.SpbHomeTitle=Allegro 用户数据目录
chinesesimp.SpbHomeDescription=选择 SPB_Data HOME，以便安全配置 pcbenv。
chinesesimp.SpbHomeSubCaption=安装程序只会添加带标记的 Moka Skill 配置；卸载时会自动移除这些配置。
chinesesimp.MenuLanguageTitle=MokaSkill 菜单栏语言
chinesesimp.MenuLanguageDescription=选择 MokaSkill 在 Allegro 中显示的中文或英文菜单栏。
chinesesimp.MenuLanguageSubCaption=中文为默认选项。选择 English 时仅菜单栏为英文，各功能界面仍使用中文。
chinesesimp.ChineseMenu=中文（默认）
chinesesimp.SpbHomeRequired=SPB_Data HOME 不能为空。
english.SpbHomeTitle=Allegro user data folder
english.SpbHomeDescription=Select SPB_Data HOME so Setup can configure pcbenv safely.
english.SpbHomeSubCaption=Setup adds only marked Moka Skill blocks and removes them automatically during uninstall.
english.MenuLanguageTitle=MokaSkill menu language
english.MenuLanguageDescription=Choose the Chinese or English MokaSkill menu bar shown in Allegro.
english.MenuLanguageSubCaption=English changes the menu bar only; all feature panels remain in Chinese.
english.ChineseMenu=Chinese (default)
english.SpbHomeRequired=SPB_Data HOME cannot be empty.
