program DOMApp;

uses
  qtx.sysutils,
  qtx.classes,
  qtx.components,
  qtx.time,
  qtx.dom.widgets,
  qtx.dom.theme,
  qtx.dom.types,
  qtx.dom.events,
  qtx.dom.graphics,
  qtx.dom.application, 
  qtx.dom.forms,
form1;
                       
begin
  TQTXDOMApplicationFull.Create(nil, procedure (Widget: TQTXComponent)
  begin
    Widget.Handle.style["font-family"] := "Segoe UI"; 
    {$I "app::form.init"}
  end);
  
end.
