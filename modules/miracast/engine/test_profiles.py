import argparse
import json
import os
import tempfile
import unittest

import profiles
import wfd

ROKU = {"name": "Roku Express - 898", "manufacturer": "Roku", "model": "Express",
        "device_type": "7-0050F204-1", "content_protection": "HDCP2.1 port=12000", "audio_codecs": ["LPCM", "AAC"]}
FIRE = {"name": "Joel's Fire TV", "manufacturer": "", "model": "UB134_STATION", "content_protection": "none",
        "audio_codecs": ["LPCM", "AAC"]}


class MatchTests(unittest.TestCase):
    def test_builtin_profiles_recognise_the_known_displays(self):
        self.assertEqual(profiles.match(profiles.BUILTIN, ROKU)["name"], "roku")
        self.assertEqual(profiles.match(profiles.BUILTIN, FIRE)["name"], "fire-tv")
        self.assertIsNone(profiles.match(profiles.BUILTIN, {"name": "bedroom tv"}))

    def test_conditions_are_anded_and_case_insensitive_regexes(self):
        p = {"name": "x", "match": {"manufacturer": "^roku$", "audio_codecs": "aac"}}
        self.assertTrue(profiles.matches(p, ROKU))
        self.assertFalse(profiles.matches(p, dict(ROKU, audio_codecs=["LPCM"])))
        self.assertFalse(profiles.matches(p, FIRE))

    def test_empty_match_matches_everything(self):
        self.assertTrue(profiles.matches({"name": "all", "match": {}}, FIRE))

    def test_user_profiles_come_first(self):
        user = [{"name": "mine", "match": {"manufacturer": "Roku"}, "settings": {"bitrate": 4000}}]
        self.assertEqual(profiles.match(user + profiles.BUILTIN, ROKU)["name"], "mine")


class ApplyTests(unittest.TestCase):
    def args(self):
        return argparse.Namespace(bitrate=12000, vbv_ms=30, audio_preference="AAC")

    def test_settings_override_defaults(self):
        a = self.args()
        applied = profiles.apply(a, set(), {"bitrate": 8000, "audio_preference": "AAC,LPCM"})
        self.assertEqual((a.bitrate, a.audio_preference), (8000, "AAC,LPCM"))
        self.assertEqual(applied, {"bitrate": 8000, "audio_preference": "AAC,LPCM"})

    def test_command_line_wins_over_a_profile(self):
        a = self.args()
        a.bitrate = 5000
        profiles.apply(a, {"bitrate"}, {"bitrate": 8000, "vbv_ms": 20})
        self.assertEqual((a.bitrate, a.vbv_ms), (5000, 20))

    def test_unknown_option_is_an_error(self):
        with self.assertRaises(ValueError):
            profiles.apply(self.args(), set(), {"no_such_option": 1})


class LoadTests(unittest.TestCase):
    def write(self, data):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump(data, f)
        self.addCleanup(os.unlink, path)
        return path

    def test_map_form_as_written_by_the_nix_option(self):
        path = self.write({"bedroom": {"match": {"name": "bedroom"}, "settings": {"bitrate": 8000}}})
        loaded = profiles.load(path)
        self.assertEqual(loaded[0]["name"], "bedroom")
        self.assertEqual(loaded[0]["settings"], {"bitrate": 8000})

    def test_list_form_and_missing_path(self):
        self.assertEqual(profiles.load(self.write([{"name": "a"}]))[0]["name"], "a")
        self.assertEqual(profiles.load(None), [])


class AudioNegotiationTests(unittest.TestCase):
    OFFER = "LPCM 00000003 00, AAC 00000001 00"

    def test_aac_by_default(self):
        self.assertEqual(wfd.choose_audio_codec(self.OFFER), ("AAC", "AAC 00000001 00"))

    def test_preference_order_is_respected(self):
        self.assertEqual(wfd.choose_audio_codec(self.OFFER, ["LPCM", "AAC"]), ("LPCM", "LPCM 00000002 00"))

    def test_lpcm_only_sink_gets_nothing_unless_asked(self):
        self.assertEqual(wfd.choose_audio_codec("LPCM 00000003 00"), (None, "none"))
        self.assertEqual(wfd.choose_audio_codec("LPCM 00000003 00", ["AAC", "LPCM"])[0], "LPCM")

    def test_only_modes_we_can_make(self):
        self.assertEqual(wfd.choose_audio_codec("AAC 00000002 00"), (None, "none"))        # 4-channel AAC only
        self.assertEqual(wfd.choose_audio_codec("LPCM 00000001 00", ["LPCM"]), (None, "none"))   # 44.1 kHz only

    def test_parse(self):
        self.assertEqual(wfd.parse_audio_codecs(self.OFFER)[1], {"codec": "AAC", "modes": 1, "latency": 0})
        self.assertEqual(wfd.parse_audio_codecs(None), [])


class EngineIntegrationTests(unittest.TestCase):
    def session(self, state, profile_file=None, argv=()):
        import asyncio
        import miracast_source as ms
        d = tempfile.mkdtemp()
        sf = os.path.join(d, "state.json")
        with open(sf, "w") as f:
            json.dump(state, f)
        parser = ms.build_parser()
        args = parser.parse_args(["--link-state", sf] + (["--profiles", profile_file] if profile_file else []) + list(argv))
        args.explicit = {k for k, v in vars(args).items() if v != parser.get_default(k)}

        class Writer:
            def get_extra_info(self, key):
                return ("10.0.0.2", 1) if key == "peername" else ("10.0.0.1", 2)

        class Status:
            def set(self, **kw):
                pass
        loop = asyncio.new_event_loop()
        self.addCleanup(loop.close)
        s = ms.Session(args, Status(), None, Writer(), loop)
        s.log = lambda m: None
        return s, args

    STATE = {"link": {"peer": "aa:bb"}, "peers": [{"address": "aa:bb", "name": "Roku Express", "manufacturer": "Roku"}]}

    def test_builtin_profile_is_found_from_the_daemon_state(self):
        s, _ = self.session(self.STATE)
        s.apply_sink_profile({"wfd_audio_codecs": "AAC 00000001 00"})
        self.assertEqual(s.sink_profile, "roku")

    def test_user_profile_settings_reach_the_engine_options(self):
        fd, path = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w") as f:
            json.dump({"slow": {"match": {"manufacturer": "roku"}, "settings": {"audio_start_delay_ms": 2000, "vbv_ms": 10}}}, f)
        self.addCleanup(os.unlink, path)
        s, args = self.session(self.STATE, path, ["--vbv-ms", "25"])
        s.apply_sink_profile({})
        self.assertEqual(s.sink_profile, "slow")
        self.assertEqual((args.audio_start_delay_ms, args.vbv_ms), (2000, 25))   # CLI option kept

    def test_unknown_display_uses_the_defaults(self):
        s, args = self.session({"link": {"peer": "cc:dd"}, "peers": []})
        s.apply_sink_profile({})
        self.assertIsNone(s.sink_profile)
        self.assertEqual(args.audio_start_delay_ms, 1000)


class LpcmPipelineTests(unittest.TestCase):
    def test_lpcm_branch_and_helper(self):
        import miracast_source as ms
        args = ms.build_parser().parse_args(["--source", "testcap"])
        cmd = " ".join(ms.build_pipeline(args, wfd.mode_of(7), wfd.PROFILE_CHP, 0x08, "127.0.0.1", 1028, 5000,
                                         audio_on=True, audio_port=9, audio_codec="LPCM"))
        self.assertIn("caps=audio/x-lpcm,width=(int)16", cmd)
        self.assertNotIn("aacparse", cmd)
        helper = " ".join(ms.build_audio_cmd(args, "LPCM"))
        self.assertIn("format=S16BE", helper)
        self.assertNotIn("fdkaacenc", helper)


if __name__ == "__main__":
    unittest.main()
