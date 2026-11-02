program NodeExecute;

uses
  qtx.sysutils,
  qtx.classes,
  qtx.components,
  qtx.time,
  app.body,
  qtx.node.application;

var
  AppInstance: TNodeApplication;

begin
  try
    AppInstance := TNodeApplication.Create(nil, procedure (Component: TQTXComponent)
    begin
      {$I "app::form.init"}
    end);
    AppInstance.Execute();
  except
    on e: exception do
    writeln(e.message);
  end;
end.
