#!/usr/bin/env python3
"""Transpile tn2019quest Bot (C#) dialog definitions to JSON for the Godot port.

Faithful subset parser: it does NOT execute the original code, it converts
DialogQuestion/DialogAnswer initializers into data the GDScript engine
interprets with exactly the original semantics (see quest_engine.gd):
answer matching, availability, inventory/journal changes, MoveToDialog,
ChangeMap, MoveToPos, map-icon dialog override, PreventMove.

Dropped on purpose (single-player port, no Telegram):
- ForPlayer turn restriction (the original gated dialogs by Telegram user)
- Telegram bot token / proxy / photo file-ids (only the local .jpg filename is kept)
- DynamicMessage lambdas: inventory/journal dialogs are rendered by the
  engine itself, keyed by dialog name (see quest_engine.gd).
"""
import json, re, sys
from pathlib import Path

SRC = Path.home() / "workspace/tn2019quest/Bot"

def decode_cs_escapes(s: str) -> str:
    out, i, units = [], 0, []
    def flush():
        nonlocal units
        j = 0
        while j < len(units):
            u = units[j]
            if 0xD800 <= u <= 0xDBFF and j + 1 < len(units) and 0xDC00 <= units[j+1] <= 0xDFFF:
                out.append(chr(0x10000 + ((u - 0xD800) << 10) + (units[j+1] - 0xDC00))); j += 2
            else:
                out.append(chr(u)); j += 1
        units = []
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i+1]
            if n == "u" and i + 5 < len(s):
                units.append(int(s[i+2:i+6], 16)); i += 6; continue
            flush()
            out.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\", '"': '"', "'": "'", "0": "\0"}.get(n, n)); i += 2; continue
        flush(); out.append(c); i += 1
    flush(); return "".join(out)

def parse_consts(text, cls):
    m = re.search(rf"public static class {cls}\s*\{{(.*?)\n    \}}", text, re.S)
    body = m.group(1)
    consts = {}
    for mm in re.finditer(r"public const (?:char|string) (\w+) = (?:'((?:\\.|[^'\\])*)'|nameof\((\w+)\))", body):
        name, ch, nm = mm.groups()
        consts[name] = decode_cs_escapes(ch) if ch is not None else nm
    return consts

strings_cs = (SRC / "Logic/Strings.cs").read_text(encoding="utf-8-sig")
MAP_ICON = parse_consts(strings_cs, "MapIcon")
MAP_BTN = parse_consts(strings_cs, "MapButtons")
# Items / quests / dialogs are nameof() constants: name == value
ITEMS = set(re.findall(r"public const string (\w+) = nameof", re.search(r"public static class Item\s*\{(.*?)\n    \}", strings_cs, re.S).group(1)))
QUESTS = set(re.findall(r"public const string (\w+) = nameof", re.search(r"public static class Quest\s*\{(.*?)\n    \}", strings_cs, re.S).group(1)))

smile_cs = (SRC / "Logic/SmileTranslator.cs").read_text(encoding="utf-8-sig")
smile_cs = "\n".join(l for l in smile_cs.split("\n") if not l.strip().startswith("//"))
EMOJI = {}
for mm in re.finditer(r"\[(MapIcon|MapButtons)\.(\w+)\]\s*=\s*\"((?:\\.|[^\"\\])*)\"", smile_cs):
    cls, name, raw = mm.groups()
    d = MAP_ICON if cls == "MapIcon" else MAP_BTN
    EMOJI[d[name]] = decode_cs_escapes(raw)

# ---------------- tokenizer ----------------
class Tok:
    def __init__(self, kind, val): self.kind, self.val = kind, val
    def __repr__(self): return f"Tok({self.kind},{self.val!r})"

def tokenize(text):
    toks, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c.isspace(): i += 1; continue
        if text.startswith("//", i):
            j = text.find("\n", i); i = n if j < 0 else j + 1; continue
        if text.startswith("/*", i):
            j = text.find("*/", i); i = n if j < 0 else j + 2; continue
        if text.startswith('$"', i) or text.startswith('@"', i):
            interp = text[i] == "$"; i += 2
            buf = []
            while i < n:
                if text[i] == '"' and not (not interp and text.startswith('""', i)):
                    i += 1; break
                if not interp and text.startswith('""', i): buf.append('"'); i += 2; continue
                buf.append(text[i]); i += 1
            toks.append(Tok("STR", ("$" if interp else "") + "".join(buf))); continue
        if c == '"':
            i += 1; buf = []
            while i < n and text[i] != '"':
                if text[i] == "\\" and i + 1 < n: buf.append(text[i:i+2]); i += 2
                else: buf.append(text[i]); i += 1
            i += 1; toks.append(Tok("STR", "".join(buf))); continue
        if c == "'":
            j = i + 1; buf = []
            while j < n and text[j] != "'":
                if text[j] == "\\" and j + 1 < n: buf.append(text[j:j+2]); j += 2
                else: buf.append(text[j]); j += 1
            toks.append(Tok("CHAR", decode_cs_escapes("".join(buf)))); i = j + 1; continue
        if c.isalpha() or c == "_":
            j = i
            while j < n and (text[j].isalnum() or text[j] == "_"): j += 1
            toks.append(Tok("ID", text[i:j])); i = j; continue
        if c.isdigit():
            j = i
            while j < n and text[j].isdigit(): j += 1
            toks.append(Tok("INT", int(text[i:j]))); i = j; continue
        two = text[i:i+2]
        if two in ("=>", "==", "!=", "&&", "||", "<=", ">="):
            toks.append(Tok("SYM", two)); i += 2; continue
        toks.append(Tok("SYM", c)); i += 1
    toks.append(Tok("EOF", None))
    return toks

def eval_interp(raw, interp):
    """Evaluate a (possibly interpolated) C# string literal body."""
    if not interp:
        return decode_cs_escapes(raw)
    out, i = [], 0
    while i < len(raw):
        if raw[i] == "{":
            j = raw.find("}", i); expr = raw[i+1:j]
            m = re.fullmatch(r"MapIcon\.(\w+)\.ToSmile\(\)", expr)
            if m: out.append(EMOJI[MAP_ICON[m.group(1)]])
            elif (m := re.fullmatch(r"MapButtons\.(\w+)\.ToString\(\)", expr)): out.append(MAP_BTN[m.group(1)])
            elif (m := re.fullmatch(r"MapIcon\.(\w+)", expr)): out.append(MAP_ICON[m.group(1)])
            else: raise ValueError(f"unresolved interpolation {{{expr}}}")
            i = j + 1
        else:
            out.append(raw[i]); i += 1
    return decode_cs_escapes("".join(out))

# ---------------- parser ----------------
class P:
    def __init__(self, toks): self.t = toks; self.i = 0
    def peek(self, k=0): return self.t[self.i + k]
    def next(self): tok = self.t[self.i]; self.i += 1; return tok
    def expect(self, kind=None, val=None):
        tok = self.next()
        assert (kind is None or tok.kind == kind) and (val is None or tok.val == val), f"expected {kind} {val}, got {tok}"
        return tok
    def accept(self, val):
        if self.peek().val == val: self.i += 1; return True
        return False
    def at_eof(self): return self.peek().kind == "EOF"

    def is_lambda_ahead(self):
        if self.peek().kind == "ID" and self.peek(1).val == "=>": return True
        if self.peek().val == "(":
            j = self.i + 1
            if self.t[j].kind == "ID":
                j += 1
                if self.t[j].val == ",": j += 2
                if self.t[j].val == ")": return self.t[j+1].val == "=>"
        return False

    def parse_value(self):
        if self.is_lambda_ahead(): return self.parse_lambda()
        tok = self.peek()
        if tok.kind == "STR":
            self.next(); s = eval_interp(tok.val[1:] if tok.val.startswith("$") else tok.val, tok.val.startswith("$"))
            while self.accept("+"):
                t2 = self.expect("STR")
                s += eval_interp(t2.val[1:] if t2.val.startswith("$") else t2.val, t2.val.startswith("$"))
            return {"t": "str", "v": s}
        if tok.kind == "CHAR": self.next(); return {"t": "char", "v": tok.val}
        if tok.kind == "INT": self.next(); return {"t": "int", "v": tok.val}
        if tok.kind == "ID":
            if tok.val == "new":
                self.next()
                if self.peek().val == "[":
                    self.next(); self.expect("SYM", "]"); self.expect("SYM", "{")
                    items = []
                    while not self.accept("}"):
                        items.append(self.parse_value())
                        self.accept(",")
                    return {"t": "arr", "v": items}
                name = self.expect("ID").val
                if name in ("DialogQuestion", "DialogAnswer"):
                    return self.parse_object(name)
                self.expect("SYM", "["); self.expect("SYM", "]"); self.expect("SYM", "{")
                items = []
                while not self.accept("}"):
                    items.append(self.parse_value())
                    self.accept(",")
                return {"t": "arr", "v": items}
            if tok.val in ("true", "false"):
                self.next(); return {"t": "bool", "v": tok.val == "true"}
            if tok.val == "null": self.next(); return {"t": "null"}
            # member chain
            parts = [self.next().val]
            while self.peek().val == ".":
                self.next(); parts.append(self.expect("ID").val)
            if self.peek().val == "(":
                self.next()
                args = []
                while not self.accept(")"):
                    args.append(self.parse_value()); self.accept(",")
                if parts == ["MapButtons"] or len(parts) >= 2 and parts[-1] == "ToString":
                    base = parts[0]
                    return {"t": "str", "v": MAP_BTN[parts[1]] if base == "MapButtons" else MAP_ICON[parts[1]]}
                raise ValueError(f"unexpected call {parts}")
            if len(parts) == 2:
                cls, name = parts
                if cls == "Dialog": return {"t": "dialog", "v": name}
                if cls == "MapIcon": return {"t": "icon", "v": MAP_ICON[name]}
                if cls == "MapButtons": return {"t": "str", "v": MAP_BTN[name]}
                if cls in ("Item", "Quest"): return {"t": "str", "v": name}
                return {"t": "ref", "var": cls, "field": name}
            if len(parts) == 1: return {"t": "var", "v": parts[0]}
            raise ValueError(f"unexpected chain {parts}")
        raise ValueError(f"unexpected token {tok}")

    def parse_object(self, kind):
        self.expect("SYM", "{"); fields = {}
        while not self.accept("}"):
            fname = self.expect("ID").val; self.expect("SYM", "=")
            fields[fname] = self.parse_value(); self.accept(",")
        return {"t": kind, "fields": fields}

    def parse_lambda(self):
        if self.peek().kind == "ID":
            params = [self.next().val]
        else:
            self.expect("SYM", "("); params = []
            while not self.accept(")"):
                params.append(self.expect("ID").val); self.accept(",")
        self.expect("SYM", "=>")
        if self.peek().val == "{":
            depth, start = 0, self.i
            while True:
                v = self.next().val
                if v == "{": depth += 1
                elif v == "}":
                    depth -= 1
                    if depth == 0: break
            return {"t": "block"}
        body = self.parse_bool()
        return {"t": "lambda", "params": params, "body": body}

    def parse_bool(self):
        left = self.parse_and()
        while self.peek().val == "||":
            self.next(); left = {"op": "or", "a": left, "b": self.parse_and()}
        return left
    def parse_and(self):
        left = self.parse_unary()
        while self.peek().val == "&&":
            self.next(); left = {"op": "and", "a": left, "b": self.parse_unary()}
        return left
    def parse_unary(self):
        if self.accept("!"): return {"op": "not", "a": self.parse_unary()}
        if self.accept("("):
            e = self.parse_bool(); self.expect("SYM", ")"); return e
        return self.parse_atom()
    def parse_atom(self):
        # chain: ident (.ident)* with optional calls, + / - ints for pos exprs
        if self.peek().kind == "INT":
            expr = {"t": "int", "v": self.next().val}
        else:
            first = self.expect("ID").val
            expr = self.parse_chain_from(first)
        while self.peek().val in ("+", "-"):
            op = self.next().val; rhs = self.parse_atom()
            expr = {"op": "add" if op == "+" else "sub", "a": expr, "b": rhs}
        return expr
    def parse_chain_from(self, first):
        parts = [first]
        while self.peek().val == ".":
            self.next(); parts.append(self.expect("ID").val)
            if self.peek().val == "(":
                self.next(); args = []
                while not self.accept(")"):
                    args.append(self.parse_bool()); self.accept(",")
                call = {"call": parts[-1], "on": parts[:-1], "args": args}
                # chained calls on result (ChangeMap / ChangeInventory / ChangeJournal)
                while self.peek().val == ".":
                    self.next(); m = self.expect("ID").val; self.expect("SYM", "(")
                    a2 = []
                    while not self.accept(")"):
                        a2.append(self.parse_bool()); self.accept(",")
                    call = {"call": m, "on": [call], "args": a2}
                return call
        if len(parts) == 1:
            if parts[0] == "pos": return {"pos": True}
            if parts[0] == "startPosition": return {"start": True}
            return {"var": parts[0]}
        if len(parts) == 2:
            cls, name = parts
            if cls == "MapIcon": return {"icon": MAP_ICON[name]}
            if cls == "NewCellQuest": raise ValueError("NewCellQuest chain needs .Map.IndexOf")
            return {"member": parts}
        if parts == ["NewCellQuest", "Map", "IndexOf"]:
            raise ValueError("IndexOf parsed as call, not here")
        return {"member": parts}

def simplify(v):
    """Convert parser values to the JSON schema the engine understands."""
    if isinstance(v, dict):
        t = v.get("t")
        if t == "str": return v["v"]
        if t == "char": return v["v"]
        if t == "int": return v["v"]
        if t == "bool": return v["v"]
        if t == "null": return None
        if t == "dialog": return {"dialog": v["v"]}
        if t == "icon": return {"icon": v["v"]}
        if t == "arr": return [simplify(x) for x in v["v"]]
        if t == "ref": return {"ref_answers": v["var"]}
        if t == "var": return {"var": v["v"]}
        if t == "block": return {"dynamic": True}
        if t == "lambda": return simplify_lambda(v["body"])
        if t in ("DialogQuestion", "DialogAnswer"): return {k: simplify(x) for k, x in v["fields"].items()}
    if isinstance(v, list): return [simplify(x) for x in v]
    return v

def _arg_name(arg):
    if isinstance(arg, dict) and arg.get("t") == "str": return arg["v"]
    if isinstance(arg, dict) and "member" in arg: return arg["member"][1]
    v = simplify(arg)
    if isinstance(v, dict) and "member" in v: return v["member"][1]
    return v

def simplify_lambda(body):
    # Available: bool tree with Has/Is* calls
    if isinstance(body, dict) and body.get("op") in ("and", "or", "not"):
        return {"cond": body["op"], **({"a": simplify_lambda(body["a"]), "b": simplify_lambda(body["b"])} if "b" in body else {"a": simplify_lambda(body["a"])})}
    if isinstance(body, dict) and "call" in body:
        call, on, args = body["call"], body["on"], body["args"]
        if call in ("Has", "IsOpen", "IsFinished", "IsKnown"):
            return {"check": call, "name": _arg_name(args[0])}
        if call in ("Give", "Take"):
            name = _arg_name(args[0])
            inner = on[0] if on else None
            seq = []
            if isinstance(inner, dict) and "call" in inner: seq = simplify_lambda(inner)["seq"]
            seq.append({"op": call, "item": name}); return {"seq": seq}
        if call in ("Open", "Finish"):
            name = _arg_name(args[0])
            inner = on[0] if on else None
            seq = []
            if isinstance(inner, dict) and "call" in inner: seq = simplify_lambda(inner)["seq"]
            seq.append({"op": call, "quest": name}); return {"seq": seq}
        if call in ("PosUp", "PosDown", "PosLeft", "PosRight"):
            return {"move": call.lower().replace("pos", ""), "of": simplify_pos(args[0])}
        if call == "IndexOf":
            # NewCellQuest.Map.IndexOf(icon) or map.IndexOf(icon)
            return {"initial_icon": simplify(args[0]) if args else None}
        if call == "ClearPos":
            return {"map_ops": [{"op": "clear", "at": simplify_pos(args[0])}]}
        if call == "Replace":
            first = args[0]
            if isinstance(first, dict) and "call" in first:
                # Replace(pos-expr, char) chained on a map value: handled below
                pass
            inner = on[0] if on else None
            ops = []
            if isinstance(inner, dict) and "call" in inner and inner["call"] in ("Replace", "ClearPos"):
                ops = simplify_lambda(inner)["map_ops"]
            target = simplify_pos(first) if isinstance(first, dict) and ("call" in first or first.get("pos") or first.get("start")) else simplify(first)
            ch = simplify(args[1])
            if isinstance(ch, dict) and ch.get("icon") is not None: ch = ch["icon"]
            if isinstance(target, dict) and target.get("icon") is not None:
                ops.append({"op": "replace_first", "icon": target["icon"], "char": ch})
            else:
                ops.append({"op": "replace_at", "at": target, "char": ch})
            return {"map_ops": ops}
        raise ValueError(f"unhandled call {call} on {on}")
    if isinstance(body, dict) and body.get("op") in ("add", "sub"):
        return {"arith": body["op"], "a": simplify_pos(body["a"]), "b": simplify_pos(body["b"])}
    if isinstance(body, dict) and body.get("pos"): return {"pos": True}
    if isinstance(body, dict) and body.get("start"): return {"start": True}
    if isinstance(body, dict) and body.get("icon") is not None: return body
    raise ValueError(f"unhandled lambda body {body!r}")

def simplify_pos(e):
    if isinstance(e, dict):
        if "call" in e: return simplify_lambda(e)
        if e.get("pos"): return {"pos": True}
        if e.get("start"): return {"start": True}
        if e.get("icon") is not None: return e
        if e.get("op") in ("add", "sub"): return simplify_lambda(e)
        if e.get("t") == "icon": return {"icon": e["v"]}
        if e.get("t") == "char": return {"icon": e["v"]}
        if e.get("t") == "int": return {"int": e["v"]}
    return simplify(e)

def parse_story(path, story):
    text = path.read_text(encoding="utf-8-sig")
    m = re.search(r'public static string Map =\s*@"(.*?)"\s*;', text, re.S)
    rows = m.group(1).strip("\n").split("\n")
    rows = [r.rstrip("\r") for r in rows]
    assert len(set(map(len, rows))) == 1, f"{story} map rows differ: {set(map(len, rows))}"
    # tokenize only the GetDialogs method body
    body = text[text.index("public static DialogQuestion[] GetDialogs()"):]
    toks = tokenize(body)
    p = P(toks)
    vars_ = {}
    order = None
    while not p.at_eof():
        tok = p.peek()
        if tok.kind == "ID" and tok.val == "var":
            p.next(); name = p.expect("ID").val; p.expect("SYM", "=")
            if name in ("initialMap", "startPosition"):
                while p.next().val != ";": pass
                continue
            val = p.parse_value(); p.accept(";")
            vars_[name] = simplify(val)
        elif tok.kind == "ID" and tok.val == "return":
            p.next(); val = p.parse_value()
            # val is arr with .Concat chains? Our parser: arr then .Concat not handled -> handle here
            order = val; break
        else:
            p.next()
    # return expression: parse_value stops at .Concat; recover concat list from tokens textually
    ret_text = body[body.index("return "):]
    concat_vars = re.findall(r"\.Concat\((\w+)\)", ret_text)
    first = re.findall(r"return new\[\]\s*\{([^}]*)\}", ret_text, re.S)[0]
    first_vars = [x.strip() for x in first.split(",") if x.strip()]
    dialogs = []
    def add_var(name):
        v = vars_[name]
        if isinstance(v, dict) and "Name" in v: dialogs.append(v)
        elif isinstance(v, list):
            for d in v:
                assert isinstance(d, dict) and "Name" in d, f"array {name} item not a dialog: {d}"
                dialogs.append(d)
        else: raise ValueError(f"var {name} is neither dialog nor array: {v!r}")
    for n in first_vars + concat_vars: add_var(n)
    return rows, dialogs

def normalize_dialog(d, story):
    name = d["Name"]["dialog"] if isinstance(d.get("Name"), dict) else d["Name"]
    answers = d.get("Answers")
    if isinstance(answers, dict) and "ref_answers" in answers:
        answers = {"ref_answers": answers["ref_answers"]}
    out = {"name": name, "story": story}
    if "Message" in d: out["message"] = d["Message"]
    if "DynamicMessage" in d: out["dynamic"] = d["DynamicMessage"].get("dynamic", True) if isinstance(d["DynamicMessage"], dict) else True
    if "Photo" in d: out["photo"] = d["Photo"].split(";")[0].split("/")[-1]
    if d.get("DisplayMap"): out["display_map"] = True
    if d.get("PreventMove"): out["prevent_move"] = True
    if "MapIcon" in d:
        mi = d["MapIcon"]
        out["map_icon"] = mi["icon"] if isinstance(mi, dict) else mi
    if answers is not None: out["answers"] = answers
    return out

def normalize_answer(a):
    out = {}
    out["message"] = a["Message"]
    if "Available" in a: out["available"] = a["Available"]
    if "IsHidden" in a and a["IsHidden"] is True: out["hidden"] = True
    if "MoveToDialog" in a:
        mt = a["MoveToDialog"]
        out["move_to_dialog"] = mt["dialog"] if isinstance(mt, dict) else mt
    if "MoveToPos" in a: out["move_to_pos"] = a["MoveToPos"]
    if "ChangeInventory" in a: out["change_inventory"] = a["ChangeInventory"]
    if "ChangeJournal" in a: out["change_journal"] = a["ChangeJournal"]
    if "ChangeMap" in a: out["change_map"] = a["ChangeMap"]
    return out

def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("data")
    tosh_rows, tosh = parse_story(SRC / "Quests/ToshikStory.cs", "toshik")
    nast_rows, nast = parse_story(SRC / "Quests/NastyaStory.cs", "nastya")
    # The original ran on Windows (CRLF), where its string-index movement
    # worked; on a plain grid the two maps just have different widths.
    # Pad Toshik rows with walls to the common width 14: every Toshik row
    # already ends in walls, so this changes no reachable cell.
    width = max(len(r) for r in tosh_rows + nast_rows)
    combined = [r.ljust(width, "#") for r in tosh_rows] + [r.ljust(width, "#") for r in nast_rows]
    dialogs = {}
    refs = {}
    for d, story in [(x, "toshik") for x in tosh] + [(x, "nastya") for x in nast]:
        nd = normalize_dialog(d, story)
        # resolve ref_answers using the story-local variable map: re-parse is avoided;
        # instead resolve later from the raw var tables (see below)
        dialogs[nd["name"]] = nd
    # Resolve Answers references: mapDialog/inventory etc are per-story; the
    # ref var name is the same across stories but the dialog set differs, so
    # resolve by looking up which dialog in the SAME story owns that var.
    # We recover that from the parse: dialogs whose answers were a ref keep it;
    # the referenced dialog is the story's map dialog (mapDialog) in every case
    # observed in the source (Answers = mapDialog.Answers). Verify by name:
    for nd in dialogs.values():
        ans = nd.get("answers")
        if isinstance(ans, dict) and "ref_answers" in ans:
            assert ans["ref_answers"] == "mapDialog", ans
            target = "MapToshik" if nd["story"] == "toshik" else "MapNastya"
            nd["answers"] = dialogs[target]["answers"]
    # normalize answers (they are already simplified dicts from parse)
    for nd in dialogs.values():
        if isinstance(nd.get("answers"), list):
            nd["answers"] = [normalize_answer(a) for a in nd["answers"]]
    # player icons: set by NewCellQuest per story
    for nd in dialogs.values():
        nd["player_icon"] = "O" if nd["story"] == "toshik" else "N"
    # start dialogs and positions
    start_tosh = combined_index(combined, "O")
    start_nast = combined_index(combined, "N")
    data = {
        "map_rows": combined,
        "width": len(combined[0]), "height": len(combined),
        "start_pos_toshik": start_tosh, "start_pos_nastya": start_nast,
        "start_dialog": "StartToshik",
        "starting_journal": ["EnterHall"],
        "emoji": EMOJI,
        "dialogs": dialogs,
        "order": [d["name"] for d in
                  [normalize_dialog(x, "toshik") for x in tosh] + [normalize_dialog(x, "nastya") for x in nast]],
    }
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "quest.json").write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"dialogs: {len(dialogs)} (toshik {len(tosh)}, nastya {len(nast)})")
    print(f"map: {len(combined)} rows x {len(combined[0])}, toshik start {start_tosh}, nastya start {start_nast}")
    n_ans = sum(len(d.get("answers", [])) for d in dialogs.values() if isinstance(d.get("answers"), list))
    print(f"answers total: {n_ans}")
    # validation
    names = set(dialogs)
    for nd in dialogs.values():
        for a in nd.get("answers", []) if isinstance(nd.get("answers"), list) else []:
            if "move_to_dialog" in a: assert a["move_to_dialog"] in names, (nd["name"], a)
    print("all move_to_dialog targets resolve OK")

def combined_index(rows, ch):
    for y, row in enumerate(rows):
        if ch in row: return [row.index(ch), y]
    raise ValueError(ch)

if __name__ == "__main__":
    main()
