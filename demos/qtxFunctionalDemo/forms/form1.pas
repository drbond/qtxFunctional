unit form1;

interface

uses
  qtx.sysutils,
  qtx.classes,
  qtx.components,
  qtx.dom.types,
  qtx.dom.events,
  qtx.dom.graphics,
  qtx.dom.widgets,
  qtx.dom.border,
  qtx.dom.theme,
  qtx.dom.application,
  qtx.dom.forms,
  qtx.dom.events.mouse,
  qtx.dom.events.pointer,
  qtx.dom.events.keyboard,
  qtx.dom.events.touch,
  qtx.dom.control.panel,
  qtx.dom.control.button,
  demos,
  demos.apps;

type

  TDemoRender = function: String;
  TDemoButtons = array of TQTXButton;

  Tform1 = class( TQTXForm )
  {$I "intf::form1"}
  private
    FHeader:  TQTXPanel;
    FContent: TQTXPanel;
    FButtons: TDemoButtons;
    function  AddBar(const Caption: String): TQTXPanel;
    procedure AddDemoButton(const Bar: TQTXPanel; const Caption: String;
      const Render: TDemoRender);
    procedure Highlight(const Active: TQTXButton);
    procedure RenderDemo(const Render: TDemoRender);
    procedure BuildUI;
  protected
    procedure FormPresented; override;
    procedure FormHidden; override;

    procedure StyleObject; override;
  public
    constructor Create(AOwner: TQTXComponent; CB: TQTXFormConstructor); override;
    destructor Destroy; override;
end;

implementation

const
  AccentColour = '#2f6fb0';

constructor Tform1.Create(AOwner: TQTXComponent; CB: TQTXFormConstructor);
begin
  inherited Create(AOwner, procedure (Form: TQTXForm)
  begin
    {$I "impl::form1"}

    BuildUI;

	if assigned( CB ) then
	  CB( self );
  end);
end;

destructor Tform1.destroy;
begin
  inherited;
end;

function Tform1.AddBar(const Caption: String): TQTXPanel;
var
  Bar: TQTXPanel;
begin
  Bar := TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdFlex;
      Panel.Style.flexWrap := 'wrap';
      Panel.Style.alignItems := 'center';
      Panel.Style.marginBottom := '6px';
    end);

  TQTXPanel.Create(Bar, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.width := '120px';
      Panel.Style.marginBottom := '8px';
      Panel.InnerHtml := '<span style="font-size:11px;font-weight:bold;letter-spacing:1px;' +
        'text-transform:uppercase;color:#8a96a3">' + Caption + '</span>';
    end);

  Result := Bar;
end;

procedure Tform1.BuildUI;
var
  Core, Apps: TQTXPanel;
begin
  // Fill the browser window instead of the designer's fixed 500px
  Style.height := '100vh';
  Style.width := '100%';
  Style.padding := '24px 32px';
  Style.overflowY := 'auto';
  Style.fontFamily := 'Ubuntu, "Segoe UI", Roboto, sans-serif';
  Style.color := '#1e2a3a';

  FHeader := TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.marginBottom := '16px';
      Panel.InnerHtml :=
        '<h1 style="margin:0;font-weight:500;font-size:28px">qtx<b>Functional</b></h1>' +
        '<div style="color:#8a96a3;margin-top:4px">Higher-order functions, lazy evaluation, ' +
        'composition, fusion and immutable data for Quartex Pascal</div>';
    end);

  Core := AddBar('Core ideas');
  AddDemoButton(Core, 'About', function: String begin Result := TDemos.Welcome; end);
  AddDemoButton(Core, 'Primes', function: String begin Result := TDemos.Primes; end);
  AddDemoButton(Core, 'Fibonacci', function: String begin Result := TDemos.Fibonacci; end);
  AddDemoButton(Core, 'Collatz', function: String begin Result := TDemos.Collatz; end);
  AddDemoButton(Core, 'Laziness', function: String begin Result := TDemos.Laziness; end);
  AddDemoButton(Core, 'Eager vs lazy', function: String begin Result := TAppDemos.EagerVsLazy; end);
  AddDemoButton(Core, 'Fusion', function: String begin Result := TDemos.Fusion; end);
  AddDemoButton(Core, 'Scan &amp; FlatMap', function: String begin Result := TAppDemos.ScanFlatMap; end);
  AddDemoButton(Core, 'Immutability', function: String begin Result := TDemos.Words; end);
  AddDemoButton(Core, 'Persistent data', function: String begin Result := TAppDemos.Persistent; end);

  Apps := AddBar('Applications');
  AddDemoButton(Apps, 'Fourier transform', function: String begin Result := TAppDemos.Fourier; end);
  AddDemoButton(Apps, 'Cellular automata', function: String begin Result := TAppDemos.Automata; end);
  AddDemoButton(Apps, 'Neural network', function: String begin Result := TAppDemos.Neural; end);
  AddDemoButton(Apps, 'Benchmarks', function: String begin Result := TAppDemos.Benchmarks; end);

  // Divider between the toolbars and the page
  TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.borderBottom := '1px solid #dde4ec';
      Panel.Style.margin := '6px 0 20px 0';
    end);

  FContent := TQTXPanel.Create(Self, procedure (Panel: TQTXPanel)
    begin
      Panel.PositionMode := cpStatic;
      Panel.DisplayMode := cdBlock;
      Panel.Style.paddingBottom := '32px';
      Panel.InnerHtml := TDemos.Welcome;
    end);

  if Length(FButtons) > 0 then
    Highlight(FButtons[0]);
end;

procedure Tform1.AddDemoButton(const Bar: TQTXPanel; const Caption: String;
  const Render: TDemoRender);
var
  Draw: TDemoRender;
  Created: TQTXButton;
begin
  Draw := Render;
  Created := TQTXButton.Create(Bar, procedure (Button: TQTXButton)
    begin
      Button.PositionMode := cpStatic;
      Button.InnerHtml := Caption;
      Button.Style.margin := '0 8px 8px 0';
      Button.Style.padding := '7px 14px';
      Button.Style.cursor := 'pointer';
      Button.Style.borderRadius := '4px';
      Button.OnClick := procedure (Sender: TObject)
        begin
          Highlight(TQTXButton(Sender));
          RenderDemo(Draw);
        end;
    end);
  FButtons.Add(Created);
end;

procedure Tform1.Highlight(const Active: TQTXButton);
var
  i: Integer;
begin
  for i := 0 to High(FButtons) do
    if FButtons[i] = Active then
    begin
      FButtons[i].Style.backgroundColor := AccentColour;
      FButtons[i].Style.borderColor := AccentColour;
      FButtons[i].Style.color := '#ffffff';
    end
    else
    begin
      FButtons[i].Style.backgroundColor := '';
      FButtons[i].Style.borderColor := '';
      FButtons[i].Style.color := '';
    end;
end;

procedure Tform1.RenderDemo(const Render: TDemoRender);
begin
  try
    FContent.InnerHtml := Render();
  except
    on E: Exception do
      FContent.InnerHtml :=
        '<p style="color:#b00020"><b>Error:</b> ' + E.Message + '</p>';
  end;
end;

procedure Tform1.StyleObject;
begin
  inherited;
end;

procedure Tform1.FormPresented;
begin
  inherited;
end;

procedure Tform1.FormHidden;
begin
  inherited;
end;


end.
