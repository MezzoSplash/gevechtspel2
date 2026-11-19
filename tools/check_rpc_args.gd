extends SceneTree
## Every call of an @rpc function passes as many arguments as the function takes (#338). A wrong count
## does not fail where it is sent: the receiving peer drops the call with "Method expected N argument(s)",
## and correct_position was silently dropped that way for months. Reads the source: every `@rpc func`
## (its required and total parameter count) and every `.rpc(` / `.rpc_id(` call of it in scripts/ and
## shared/, with the first argument of rpc_id (the target peer) not counted.
##   godot --headless -s res://tools/check_rpc_args.gd

var fails := 0


func _init() -> void:
	var funcs := {} # name -> [required, total]
	var files := _gd_files("res://scripts") + _gd_files("res://shared")
	for path in files:
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			if not lines[i].begins_with("@rpc"):
				continue
			var j := i + 1
			while j < lines.size() and not lines[j].begins_with("func "):
				j += 1
			if j >= lines.size():
				continue
			var head := ""
			var k := j
			while k < lines.size():
				head += lines[k]
				if head.contains(")"):
					break
				k += 1
			var fname := head.substr(5, head.find("(") - 5).strip_edges()
			var params := _split_args(head.substr(head.find("(") + 1, head.rfind(")") - head.find("(") - 1))
			var required := 0
			for prm in params:
				if not prm.contains("="):
					required += 1
			funcs[fname] = [required, params.size()]
	var calls := 0
	var re := RegEx.create_from_string("\\b(\\w+)\\.(rpc|rpc_id)\\(")
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		for m in re.search_all(text):
			var fname := m.get_string(1)
			if not funcs.has(fname):
				continue
			var args := _split_args(_balanced(text, m.get_end()))
			var n := args.size() - (1 if m.get_string(2) == "rpc_id" else 0)
			var want: Array = funcs[fname]
			calls += 1
			if n < int(want[0]) or n > int(want[1]):
				var line := text.substr(0, m.get_start()).count("\n") + 1
				_ok(false, "%s:%d %s.%s passes %d argument(s), %s takes %d..%d" % [path.get_file(), line, fname, m.get_string(2), n, fname, want[0], want[1]])
	_ok(funcs.size() > 30, "found the RPCs (%d)" % funcs.size())
	_ok(calls > 50, "checked the calls (%d)" % calls)
	print("RPC ARGS CHECK %s (%d failures)" % ["OK" if fails == 0 else "FAILED", fails])
	quit(0 if fails == 0 else 1)


func _ok(c: bool, msg: String) -> void:
	print("  %s %s" % ["PASS" if c else "FAIL", msg])
	if not c:
		fails += 1


func _gd_files(dir: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out


## The text between the "(" just before `from` and its matching ")".
func _balanced(text: String, from: int) -> String:
	var depth := 1
	var i := from
	var in_str := false
	while i < text.length() and depth > 0:
		var c := text[i]
		if c == "\"":
			in_str = not in_str
		elif not in_str:
			if c in "([{":
				depth += 1
			elif c in ")]}":
				depth -= 1
		i += 1
	return text.substr(from, i - 1 - from)


## Top-level comma split (nested calls, arrays and strings stay whole). Empty -> [].
func _split_args(s: String) -> Array:
	var out := []
	var depth := 0
	var in_str := false
	var cur := ""
	for c in s:
		if c == "\"":
			in_str = not in_str
		elif not in_str:
			if c in "([{":
				depth += 1
			elif c in ")]}":
				depth -= 1
			elif c == "," and depth == 0:
				out.append(cur)
				cur = ""
				continue
		cur += c
	if cur.strip_edges() != "":
		out.append(cur)
	var clean := []
	for a in out:
		var t: String = a.strip_edges()
		if t != "" and not t.begins_with("#"):
			clean.append(t)
	return clean
