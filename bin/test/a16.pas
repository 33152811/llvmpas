unit a16;

interface
{ ���Է��غ���ָ��ı��ʽ�ܲ�����ȷ��ת�ɵ��û�ȡָ��
}
implementation

procedure test;
type
	TMyFunc = function : Integer;
var
	a: function: Integer;
	i: Integer;
	p: pointer;
	
	procedure aaa(a: integer);
	begin
	end;
begin
	p := nil;
	i := TMyFunc(p) + 2;
	aaa(TMyFunc(p));
end;

end.