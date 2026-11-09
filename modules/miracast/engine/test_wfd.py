"""Unit tests for wfd.py (pure protocol logic). Run:  python3 -m unittest test_wfd"""
import unittest

import wfd

# Typical sink capability reply (shaped like the ones real TVs send).
SINK_VIDEO = "38 00 02 08 0001FFFF 1CFFFFFF 00000FFF 00 0000 0000 00 none none"


class Framing(unittest.TestCase):
    def test_roundtrip_request(self):
        raw = wfd.build_request("OPTIONS", "*", 1, {"Require": "org.wfa.wfd1.0"})
        m = wfd.parse_message(raw.decode())
        self.assertEqual(m.method, "OPTIONS")
        self.assertEqual(m.uri, "*")
        self.assertEqual(m.cseq, 1)
        self.assertEqual(m.headers["require"], "org.wfa.wfd1.0")

    def test_response_with_body(self):
        raw = wfd.build_response(2, body="wfd_video_formats: none\r\n")
        self.assertEqual(wfd.message_length(raw), len(raw))
        m = wfd.parse_message(raw.decode())
        self.assertTrue(m.is_response)
        self.assertEqual(m.status, 200)
        self.assertEqual(m.cseq, 2)
        self.assertEqual(wfd.parse_params(m.body), {"wfd_video_formats": "none"})

    def test_incomplete_messages(self):
        raw = wfd.build_response(2, body="abc\r\n")
        self.assertIsNone(wfd.message_length(raw[:-2]))        # body cut short
        self.assertIsNone(wfd.message_length(raw[:10]))        # headers cut short
        two = raw + raw
        self.assertEqual(wfd.message_length(two), len(raw))    # first of two

    def test_content_length_counts_bytes(self):
        raw = wfd.build_request("SET_PARAMETER", "rtsp://localhost/wfd1.0", 4, body="é\r\n")
        self.assertIn(b"Content-Length: 4", raw)               # é is 2 bytes

    def test_status_error(self):
        m = wfd.parse_message("RTSP/1.0 400 Bad Request\r\nCSeq: 5\r\n\r\n")
        self.assertEqual(m.status, 400)

    def test_garbage(self):
        with self.assertRaises(wfd.RtspError):
            wfd.parse_message("")


class VideoNegotiation(unittest.TestCase):
    def test_parse(self):
        e = wfd.parse_video_formats(SINK_VIDEO)
        self.assertEqual(len(e), 1)
        self.assertEqual(e[0]["profile"], 0x02)      # CHP only in this fixture
        self.assertEqual(e[0]["level"], 0x08)
        self.assertEqual(e[0]["cea"], 0x0001FFFF)

    def test_none(self):
        self.assertEqual(wfd.parse_video_formats("none"), [])

    def test_choose_prefers_1080p30(self):
        e = wfd.parse_video_formats(SINK_VIDEO)
        profile, level, bit = wfd.choose_video(e)
        self.assertEqual(bit, 7)
        self.assertEqual(profile, wfd.PROFILE_CHP)
        self.assertEqual(level, 0x08)

    def test_choose_falls_back(self):
        # only 720p30 (bit 5) available
        e = wfd.parse_video_formats("00 00 01 04 00000020 00000000 00000000 00 0000 0000 00 none none")
        profile, level, bit = wfd.choose_video(e)
        self.assertEqual((profile, level, bit), (wfd.PROFILE_CBP, 0x04, 5))

    def test_choose_none_supported(self):
        e = wfd.parse_video_formats("00 00 01 04 00000001 00000000 00000000 00 0000 0000 00 none none")
        self.assertEqual(wfd.choose_video(e, preference=[7]), None)

    def test_multiple_codec_entries(self):
        v = ("38 00 01 02 00000001 00000000 00000000 00 0000 0000 00 none none, "
             "02 04 00000080 00000000 00000000 00 0000 0000 00 none none")
        e = wfd.parse_video_formats(v)
        self.assertEqual(len(e), 2)
        self.assertEqual(e[1]["cea"], 0x80)

    def test_level_capped_at_41(self):
        e = wfd.parse_video_formats("00 00 01 1F 00000080 00000000 00000000 00 0000 0000 00 none none")
        self.assertEqual(wfd.choose_video(e)[1], 0x08)

    def test_fire_tv_level_31_means_720p30(self):
        # What the real Fire TV sent: CBP, level 3.1, modes 640x480p60 / 720p30 / 1080p30.
        e = wfd.parse_video_formats("38 00 01 01 000000a1 00000000 00000000 00 0000 0000 00 none none")
        self.assertEqual(wfd.choose_video(e), (wfd.PROFILE_CBP, 0x01, 5))     # not 1080p30: level 3.1 can't carry it

    def test_fits_level(self):
        self.assertTrue(wfd.fits_level(5, 0x01))       # 720p30 at 3.1
        self.assertFalse(wfd.fits_level(7, 0x01))      # 1080p30 at 3.1
        self.assertTrue(wfd.fits_level(7, 0x04))       # 1080p30 at 4.0
        self.assertFalse(wfd.fits_level(8, 0x08))      # 1080p60 at 4.1
        self.assertTrue(wfd.fits_level(8, 0x10))       # 1080p60 at 4.2

    def test_selection_string(self):
        self.assertEqual(wfd.format_video_selection(1, 4, 7),
                         "00 00 01 04 00000080 00000000 00000000 00 0000 0000 00 none none")
        self.assertEqual(wfd.mode_of(7), {"width": 1920, "height": 1080, "fps": 30, "interlaced": False})


class Params(unittest.TestCase):
    def test_m4_body(self):
        b = wfd.build_m4_body("192.168.49.40", "RTP/AVP/UDP;unicast 19000 0 mode=play",
                              "00 00 01 04 00000080 00000000 00000000 00 0000 0000 00 none none")
        p = wfd.parse_params(b)
        self.assertEqual(p["wfd_presentation_URL"], "rtsp://192.168.49.40/wfd1.0/streamid=0 none")
        self.assertEqual(p["wfd_audio_codecs"], "none")

    def test_ports(self):
        self.assertEqual(wfd.parse_client_rtp_port("RTP/AVP/UDP;unicast 19000 0 mode=play"), 19000)
        self.assertEqual(wfd.parse_transport_client_port("RTP/AVP/UDP;unicast;client_port=19000-19001"), 19000)
        with self.assertRaises(wfd.RtspError):
            wfd.parse_client_rtp_port("garbage")
        with self.assertRaises(wfd.RtspError):
            wfd.parse_transport_client_port("RTP/AVP/UDP;unicast")


class LenientAndAudio(unittest.TestCase):
    FIRE = wfd.parse_video_formats("38 00 01 01 000000a1 00000000 00000000 00 0000 0000 00 none none")

    def test_lenient_picks_1080p30_and_encodes_at_level_4(self):
        profile, level, bit = wfd.choose_video(self.FIRE, strict=False)
        self.assertEqual((level, bit), (0x01, 7))
        self.assertEqual(wfd.level_for_mode(wfd.mode_of(bit), level), 0x04)

    def test_choose_audio(self):
        self.assertEqual(wfd.choose_audio("LPCM 00000002 00, AAC 00000001 00"), "AAC 00000001 00")
        self.assertEqual(wfd.choose_audio("LPCM 00000002 00"), "none")
        self.assertEqual(wfd.choose_audio(None), "none")


class EngineArgsTests(unittest.TestCase):
    """Every option build_pipeline reads must exist in the parser (a deleted option once crashed every
    stream at PLAY and looked like the TV hanging up)."""

    def test_pipelines_build_from_default_args(self):
        import miracast_source as ms
        mode = wfd.mode_of(7)
        for source in ("test", "testcap", "portal"):
            args = ms.build_parser().parse_args(["--source", source])
            for hw in (False, True):
                cmd = ms.build_pipeline(args, mode, wfd.PROFILE_CHP, 0x08, "127.0.0.1", 1028, 5000,
                                        portal_fd=7, portal_node="62", audio_on=True, hw=hw)
                self.assertEqual(cmd[0], "gst-launch-1.0")
                self.assertIn("x264enc" if not (hw and source == "portal") else "vah264enc", cmd)

    def test_look_flags_are_parsed(self):
        import miracast_source as ms
        a = ms.build_parser().parse_args(["--color", "bt709-full", "--pattern", "smpte", "--preset", "faster",
                                          "--contrast", "1.1", "--saturation", "1.2", "--gamma", "1.1",
                                          "--brightness", "0.05", "--vbv-ms", "20"])
        cmd = ms.build_pipeline(a, wfd.mode_of(7), wfd.PROFILE_CBP, 0x04, "127.0.0.1", 1028, 5000, audio_on=False)
        text = " ".join(cmd)
        for needle in ("pattern=smpte", "speed-preset=faster", "videobalance", "gamma", "vbv-buf-capacity=20"):
            self.assertIn(needle, text)


class AudioPipeTests(unittest.TestCase):
    def test_audio_comes_from_udp_when_given_a_port(self):
        import miracast_source as ms
        args = ms.build_parser().parse_args(["--source", "testcap"])
        cmd = ms.build_pipeline(args, wfd.mode_of(7), wfd.PROFILE_CHP, 0x08, "127.0.0.1", 1028, 5000,
                                audio_on=True, audio_port=9)
        text = " ".join(cmd)
        self.assertIn("udpsrc address=127.0.0.1 port=9 do-timestamp=true", text)
        self.assertIn("framed=(boolean)true", text)             # caps known up front -> audio is in the first PMT
        self.assertNotIn("fdkaacenc", text)                      # the encoder lives in the helper process
        helper = " ".join(ms.build_audio_cmd(args))
        self.assertIn("fdkaacenc", helper)
        self.assertTrue(helper.endswith("fdsink fd=1"))


class AdtsTests(unittest.TestCase):
    def frame(self, length, id_bit=0):
        h = bytearray([0xFF, 0xF0 | (id_bit << 3) | 0x01, 0x4C, 0x80, 0, 0, 0xFC])
        h[3] = (h[3] & 0xFC) | ((length >> 11) & 3)
        h[4] = (length >> 3) & 0xFF
        h[5] = ((length & 7) << 5) | 0x1F
        return bytes(h) + bytes(length - 7)

    def test_sets_the_mpeg2_id_bit_and_keeps_everything_else(self):
        f = self.frame(40)
        out, rest = wfd.adts_to_mpeg2(f + f)
        self.assertEqual(rest, b"")
        self.assertEqual(out[:2], bytes([0xFF, 0xF9]))
        self.assertEqual(out[7:40], f[7:40])
        self.assertEqual(out[40:42], bytes([0xFF, 0xF9]))

    def test_keeps_a_partial_frame_for_later(self):
        f = self.frame(50)
        out, rest = wfd.adts_to_mpeg2(f + f[:20])
        self.assertEqual(len(out), 50)
        self.assertEqual(rest, f[:20])
        out2, rest2 = wfd.adts_to_mpeg2(rest + f[20:])
        self.assertEqual((len(out2), rest2), (50, b""))

    def test_resyncs_after_garbage(self):
        out, rest = wfd.adts_to_mpeg2(b"\x12\x34" + self.frame(30))
        self.assertEqual(out[:2], bytes([0xFF, 0xF9]))


class SplitAdtsTests(unittest.TestCase):
    def test_splits_into_single_frames(self):
        f = AdtsTests.frame(AdtsTests(), 33)
        g = AdtsTests.frame(AdtsTests(), 70)
        self.assertEqual(wfd.split_adts(f + g + f), [f, g, f])


if __name__ == "__main__":
    unittest.main()
