#!/usr/bin/env python3
"""Exercise the shipped 14-key schema against a real librime (Python stdlib only).

Example on Windows, using the official librime 1.12.0 binary distribution:
  python tools/validate-keys14-rime.py --rime-dir ../toolchains/rime-1.12.0/dist
The test deploys the same files as the plugin into a temporary workspace.
It never opens the user's real Rime profile.
"""

import argparse
import ctypes as C
import json
from pathlib import Path
import re
import shutil
import tempfile


class Traits(C.Structure):
    _fields_ = [("data_size", C.c_int)] + [
        (name, C.c_char_p) for name in (
            "shared_data_dir", "user_data_dir", "distribution_name",
            "distribution_code_name", "distribution_version", "app_name"
        )
    ] + [("modules", C.c_void_p), ("min_log_level", C.c_int)] + [
        (name, C.c_char_p) for name in ("log_dir", "prebuilt_data_dir", "staging_dir")
    ]


class Candidate(C.Structure):
    _fields_ = [("text", C.c_char_p), ("comment", C.c_char_p), ("reserved", C.c_void_p)]


class CandidateIterator(C.Structure):
    _fields_ = [("ptr", C.c_void_p), ("index", C.c_int), ("candidate", Candidate)]


class Commit(C.Structure):
    _fields_ = [("data_size", C.c_int), ("text", C.c_char_p)]


class Composition(C.Structure):
    _fields_ = [(name, C.c_int) for name in (
        "length", "cursor_pos", "sel_start", "sel_end"
    )] + [("preedit", C.c_char_p)]


class Menu(C.Structure):
    _fields_ = [(name, C.c_int) for name in (
        "page_size", "page_no", "is_last_page", "highlighted_candidate_index", "num_candidates"
    )] + [("candidates", C.POINTER(Candidate)), ("select_keys", C.c_char_p)]


class Context(C.Structure):
    _fields_ = [("data_size", C.c_int), ("composition", Composition), ("menu", Menu),
                ("commit_text_preview", C.c_char_p), ("select_labels", C.c_void_p)]


class Status(C.Structure):
    _fields_ = [("data_size", C.c_int), ("schema_id", C.c_char_p), ("schema_name", C.c_char_p)] + [
        (name, C.c_int) for name in (
            "is_disabled", "is_composing", "is_ascii_mode", "is_full_shape",
            "is_simplified", "is_traditional", "is_ascii_punct"
        )
    ]


def sized(cls):
    value = cls()
    value.data_size = C.sizeof(cls) - C.sizeof(C.c_int)
    return value


def decode(value):
    return (value or b"").decode("utf-8")


class Rime:
    def __init__(self, distribution):
        # Read the ABI order from the headers packaged with the tested DLL.
        header = (distribution / "include/rime_api.h").read_text(encoding="utf-8")
        body = header.split("rime_api_t) {", 1)[1].split("} RIME_FLAVORED(RimeApi)", 1)[0]
        names = re.findall(r"\(\*(\w+)\)", body)

        class Api(C.Structure):
            _fields_ = [("data_size", C.c_int)] + [(name, C.c_void_p) for name in names]

        self.library = C.CDLL(str(distribution / "lib/rime.dll"))
        self.library.rime_get_api.restype = C.POINTER(Api)
        self.api = self.library.rime_get_api().contents

    def function(self, name, result, *args):
        offset = getattr(type(self.api), name).offset
        assert offset < self.api.data_size + C.sizeof(C.c_int), f"Unavailable API: {name}"
        pointer = getattr(self.api, name)
        assert pointer, f"Unavailable API: {name}"
        return C.CFUNCTYPE(result, *args)(pointer)


def run(distribution, work_root):
    repo = Path(__file__).resolve().parents[1]
    source = repo / "plugin/rime/src/main/cpp"
    rime = Rime(distribution)
    api = rime.function
    session_type = C.c_size_t
    version = decode(api("get_version", C.c_char_p)())
    print(f"Testing librime {version}")
    with tempfile.TemporaryDirectory(prefix="keys14-", dir=work_root) as temporary:
        root = Path(temporary)
        shared, user = root / "shared", root / "user"
        shared.mkdir()
        user.mkdir()
        # A user's full-pinyin customization must not replace the 14-key index.
        (user / "luna_pinyin.custom.yaml").write_text(
            "patch:\n  speller/algebra: []\n  schema/name: Custom full pinyin\n", encoding="utf-8"
        )
        # Follow the install list, so a missing packaged schema fails this test.
        install = (source / "CMakeLists.txt").read_text().split("install(FILES", 1)[1]
        install = install.split("DESTINATION", 1)[0]
        for item in re.findall(r'"([^"\n]+)"', install):
            shutil.copy2(source / item, shared / Path(item).name)
        shutil.copytree(repo / "lib/fcitx5/src/main/cpp/prebuilt/opencc/data", shared / "opencc")
        traits = sized(Traits)
        traits.shared_data_dir = str(shared).encode()
        traits.user_data_dir = str(user).encode()
        traits.app_name = b"rime.keys14_test"
        traits.min_log_level = 2
        traits.log_dir = str(root).encode()
        api("setup", None, C.POINTER(Traits))(C.byref(traits))
        api("initialize", None, C.POINTER(Traits))(C.byref(traits))
        try:
            api("start_maintenance", C.c_int, C.c_int)(1)
            api("join_maintenance_thread", None)()
            session = api("create_session", session_type)()
            assert session, "Failed to create Rime session"
            select_schema = api("select_schema", C.c_int, session_type, C.c_char_p)
            assert select_schema(session, b"keys14_pinyin"), "14-key schema deployment failed"
            status = sized(Status)
            assert api("get_status", C.c_int, session_type, C.POINTER(Status))(session, C.byref(status))
            try:
                assert decode(status.schema_name) == "14键拼音", "Automatic layout marker changed"
            finally:
                api("free_status", C.c_int, C.POINTER(Status))(C.byref(status))
            api("set_option", None, session_type, C.c_char_p, C.c_int)(session, b"zh_hans", 1)
            process = api("process_key", C.c_int, session_type, C.c_int, C.c_int)
            clear = api("clear_composition", None, session_type)

            def type_keys(keys):
                clear(session)
                for key in keys:
                    assert process(session, ord(key), 0), f"Unhandled key {key!r} in {keys!r}"

            comments = {}

            def candidates():
                comments.clear()
                iterator = CandidateIterator()
                begin = api("candidate_list_begin", C.c_int, session_type, C.POINTER(CandidateIterator))
                advance = api("candidate_list_next", C.c_int, C.POINTER(CandidateIterator))
                end = api("candidate_list_end", None, C.POINTER(CandidateIterator))
                values = []
                if begin(session, C.byref(iterator)):
                    try:
                        while len(values) < 256 and advance(C.byref(iterator)):
                            text = decode(iterator.candidate.text)
                            values.append(text)
                            comments.setdefault(text, decode(iterator.candidate.comment))
                    finally:
                        end(C.byref(iterator))
                return values

            def preedit():
                context = sized(Context)
                assert api("get_context", C.c_int, session_type, C.POINTER(Context))(session, C.byref(context))
                try:
                    return decode(context.composition.preedit)
                finally:
                    api("free_context", C.c_int, C.POINTER(Context))(C.byref(context))

            def commit():
                value = sized(Commit)
                assert api("get_commit", C.c_int, session_type, C.POINTER(Commit))(session, C.byref(value))
                try:
                    return decode(value.text)
                finally:
                    api("free_commit", C.c_int, C.POINTER(Commit))(C.byref(value))

            # Literal key sequences are independent of the production xlit rule.
            # "bu" must resolve BOTH ambiguous positions: BN+UI -> bu OR ni.
            cases = [
                ("bu", ["你", "不"]),
                ("mu", ["米", "木"]),
                ("agu", ["是", "书"]),
                ("bugao", ["你好"]),
                ("bu'gao", ["你好"]),
                ("zgobgguo", ["中国"]),
                ("zuezu", ["学习"]),
                ("agueu", ["输入"]),
                ("qomeb", ["我们"]),
                ("lcae", ["绿色"]),
            ]
            for keys, expected in cases:
                type_keys(keys)
                values = candidates()
                assert all(word in values for word in expected), (keys, expected, values[:20])
                if "你好" in expected:
                    assert comments["你好"] == "ni hao", "Candidate hint did not restore full pinyin"
                print(json.dumps({"keys": keys, "preedit": preedit(), "expected": expected,
                                  "ranks": [values.index(word) + 1 for word in expected],
                                  "hints": [comments[word] for word in expected]}, ensure_ascii=False))

            type_keys("bugao")
            before = preedit()
            assert process(session, 0xFF08, 0)  # BackSpace
            assert preedit() != before, "Backspace did not edit the composition"
            assert process(session, ord("o"), 0)
            values = candidates()
            assert "你好" in values
            assert api("select_candidate", C.c_int, session_type, C.c_size_t)(session, values.index("你好"))
            assert commit() == "你好", "Candidate selection committed spelling codes"

            type_keys("bugao")
            first = candidates()[0]
            assert process(session, ord(" "), 0)
            assert commit() == first, "Space failed to commit the first candidate"

            # Existing full pinyin must retain its original spelling index.
            assert select_schema(session, b"luna_pinyin_simp")
            type_keys("nihao")
            assert "你好" in candidates(), "Standard full-pinyin regression"
            print("PASS: ambiguity, phrases, separator, deletion, selection, space and full pinyin")
        finally:
            api("finalize", None)()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rime-dir", required=True, type=Path, help="Official librime dist directory")
    parser.add_argument("--work-dir", type=Path, help="Parent directory for the temporary test profile")
    arguments = parser.parse_args()
    run(arguments.rime_dir.resolve(), arguments.work_dir)
