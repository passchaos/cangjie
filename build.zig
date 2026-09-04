const std = @import("std");

const retained_use_fixture_hashes = [_][]const u8{
    "23406a60ab081c4fb15e1596ea1cd4f27ae8443e",
    "2a670df15b73a5dc75a5cc491bde5ac93c5077dc",
    "4afb0e8b9a86bb9bd73a1247de4e33fbe3c1fd93",
    "4cce528e99f600ed9c25a2b69e32eb94a03b4ae8",
    "573d3a3177c9a8646e94c8a0d7b224334340946a",
    "6ff0fbead4462d9f229167b4e6839eceb8465058",
    "7c24183f26d60df414578a0a9f5e79ab9d32a22b",
    "dcf774ca21062e7439f98658b18974ea8b956d0c",
    "f518eb6f6b5eec2946c9fbbbde44e45d46f5e2ac",
    "fbb6c84c9e1fe0c39e152fbe845e51fd81f6748e",
};

const retained_compact_use_gates = [_]struct {
    font_hash: []const u8,
    text_file: []const u8,
}{
    .{
        .font_hash = "96490dd2ff81233b335a650e7eb660e0e7b2eeea",
        .text_file = "tests/data/cham-use-font1.txt",
    },
    .{
        .font_hash = "e68a88939e0f06e34d2bc911f09b70890289c8fd",
        .text_file = "tests/data/cham-use-font2.txt",
    },
    .{
        .font_hash = "074a5ae6b19de8f29772fdd5df2d3d833f81f5e6",
        .text_file = "tests/data/grantha-use-font1.txt",
    },
    .{
        .font_hash = "23406a60ab081c4fb15e1596ea1cd4f27ae8443e",
        .text_file = "tests/data/saurashtra-use-font1.txt",
    },
    .{
        .font_hash = "373e67bf41ca264e260a9716162b71a23549e885",
        .text_file = "tests/data/saurashtra-use-font2.txt",
    },
    .{
        .font_hash = "59a585a63b3df608fbeef00956c8c108deec7de6",
        .text_file = "tests/data/batak-use-tests.txt",
    },
    .{
        .font_hash = "1ed7e9064f008f62de6ff0207bb4dd29409597a5",
        .text_file = "tests/data/brahmi-use-font1.txt",
    },
    .{
        .font_hash = "28f497629c04ceb15546c9a70e0730125ed6698d",
        .text_file = "tests/data/brahmi-use-font2.txt",
    },
    .{
        .font_hash = "86cdd983c4e4c4d7f27dd405d6ceb7d4b9ed3d35",
        .text_file = "tests/data/sharada-use-tests.txt",
    },
    .{
        .font_hash = "3c96e7a303c58475a8c750bf4289bbe73784f37d",
        .text_file = "tests/data/use-indic3-tests.txt",
    },
    .{
        .font_hash = "3cc01fede4debd4b7794ccb1b16cdb9987ea7571",
        .text_file = "tests/data/tai-tham-use-syllable-tests.txt",
    },
    .{
        .font_hash = "573d3a3177c9a8646e94c8a0d7b224334340946a",
        .text_file = "tests/data/newa-use-font1.txt",
    },
    .{
        .font_hash = "2a670df15b73a5dc75a5cc491bde5ac93c5077dc",
        .text_file = "tests/data/chakma-use-tests.txt",
    },
    .{
        .font_hash = "a56745bac8449d0ad94918b2bb5930716ba02fe3",
        .text_file = "tests/data/newa-use-font2.txt",
    },
    .{
        .font_hash = "d0430ea499348c420946f6abc2efc84fdf8f00e3",
        .text_file = "tests/data/newa-use-font3.txt",
    },
    .{
        .font_hash = "65d1b9099cfb3191931d8d6112d7a03d979d579f",
        .text_file = "tests/data/grantha-use-font2.txt",
    },
    .{
        .font_hash = "f70f345188472b93f565d1d7fae8c668dd6a3244",
        .text_file = "tests/data/javanese-use-tests.txt",
    },
    .{
        .font_hash = "85414f2552b654585b7a8d13dcc3e8fd9f7970a3",
        .text_file = "tests/data/marchen-use-tests.txt",
    },
    .{
        .font_hash = "46669c8860cbfea13562a6ca0d83130ee571137b",
        .text_file = "tests/data/use-vowel-letter-spoofing.txt",
    },
};

const retained_morx_rearrangement_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
}{
    .{ .font_file = "TestMORXTwo.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXTwo.txt" },
    .{ .font_file = "TestMORXThree.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXThree.txt" },
    .{ .font_file = "TestMORXFour.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXFour.txt" },
    .{ .font_file = "TestMORXEight.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXEight.txt" },
    .{ .font_file = "TestMORXNine.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXNine.txt" },
    .{ .font_file = "TestMORXTen.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXTen.txt" },
    .{ .font_file = "TestMORXEleven.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXEleven.txt" },
    .{ .font_file = "TestMORXTwelve.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXTwelve.txt" },
    .{ .font_file = "TestMORXThirteen.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXThirteen.txt" },
    .{ .font_file = "TestMORXFourteen.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXFourteen.txt" },
    .{ .font_file = "TestMORXSixteen.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXSixteen.txt" },
    .{ .font_file = "TestMORXSeventeen.ttf", .text_file = "tests/data/aat/morx-rearrangement/TestMORXSeventeen.txt" },
};

const retained_morx_contextual_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8 = "ltr",
}{
    .{ .font_file = "TestMORXEighteen.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXEighteen.txt" },
    .{ .font_file = "TestMORXTwenty.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXTwenty.txt" },
    .{ .font_file = "TestMORXTwentyone.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXTwentyone.txt" },
    .{ .font_file = "TestMORXTwentytwo.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXTwentytwo.txt" },
    .{ .font_file = "TestMORXTwentythree.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXTwentythree.txt" },
    .{ .font_file = "TestMORXTwentyfive.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXTwentyfive.txt" },
    .{ .font_file = "TestMORXTwentysix.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXTwentysix.txt" },
    .{ .font_file = "TestMORXThirtyseven.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXThirtyseven-ltr.txt" },
    .{ .font_file = "TestMORXThirtyseven.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXThirtyseven-rtl.txt", .direction = "rtl" },
    .{ .font_file = "TestMORXThirtyeight.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXThirtyeight-ltr.txt" },
    .{ .font_file = "TestMORXThirtyeight.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXThirtyeight-rtl.txt", .direction = "rtl" },
    .{ .font_file = "TestMORXThirtynine.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXThirtynine-ltr.txt" },
    .{ .font_file = "TestMORXThirtynine.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXThirtynine-rtl.txt", .direction = "rtl" },
    .{ .font_file = "TestMORXForty.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXForty-ltr.txt" },
    .{ .font_file = "TestMORXForty.ttf", .text_file = "tests/data/aat/morx-contextual/TestMORXForty-rtl.txt", .direction = "rtl" },
};

const retained_morx_insertion_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
}{
    .{ .font_file = "TestMORXTwentynine.ttf", .text_file = "tests/data/aat/morx-insertion/TestMORXTwentynine.txt" },
    .{ .font_file = "TestMORXThirtyone.ttf", .text_file = "tests/data/aat/morx-insertion/TestMORXThirtyone.txt" },
    .{ .font_file = "TestMORXThirtytwo.ttf", .text_file = "tests/data/aat/morx-insertion/TestMORXThirtytwo.txt" },
    .{ .font_file = "TestMORXThirtythree.ttf", .text_file = "tests/data/aat/morx-insertion/TestMORXThirtythree.txt" },
    .{ .font_file = "TestMORXThirtyfive.ttf", .text_file = "tests/data/aat/morx-insertion/TestMORXThirtyfive.txt" },
};

const retained_morx_complete_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
}{
    .{ .font_file = "TestMORXOne.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXOne.txt" },
    .{ .font_file = "TestMORXTwo.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXTwo.txt" },
    .{ .font_file = "TestMORXFour.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXFour.txt" },
    .{ .font_file = "TestMORXEighteen.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXEighteen.txt" },
    .{ .font_file = "TestMORXTwentyseven.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXTwentyseven.txt" },
    .{ .font_file = "TestMORXTwentyeight.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXTwentyeight.txt" },
    .{ .font_file = "TestMORXTwentynine.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXTwentynine.txt" },
    .{ .font_file = "TestMORXFourtyone.ttf", .text_file = "tests/data/aat/morx-complete/TestMORXFourtyone.txt" },
};

const retained_morx_rejection_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
}{
    .{ .font_file = "TestMORXTwentyfour.ttf", .text = "ABCDE" },
    .{ .font_file = "TestMORXThirtyfour.ttf", .text = "ha" },
    .{ .font_file = "TestMORXThirtysix.ttf", .text = "A" },
};

const retained_corpus_parity_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8,
    language: ?[]const u8 = null,
}{
    .{
        .font_file = "fonts/Roboto-Regular.ttf",
        .text_file = "texts/en-words.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/Roboto-Regular.ttf",
        .text_file = "texts/en-thelittleprince.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/Amiri-Regular.ttf",
        .text_file = "texts/fa-words.txt",
        .direction = "rtl",
    },
    .{
        .font_file = "fonts/Amiri-Regular.ttf",
        .text_file = "texts/fa-thelittleprince.txt",
        .direction = "rtl",
    },
    .{
        .font_file = "fonts/SourceSerifVariable-Roman.ttf",
        .text_file = "texts/en-words.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/SourceSerifVariable-Roman.ttf",
        .text_file = "texts/en-thelittleprince.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/NotoNastaliqUrdu-Regular.ttf",
        .text_file = "texts/fa-words.txt",
        .direction = "rtl",
        .language = "dflt",
    },
    .{
        .font_file = "fonts/NotoNastaliqUrdu-Regular.ttf",
        .text_file = "texts/fa-thelittleprince.txt",
        .direction = "rtl",
        .language = "dflt",
    },
    .{
        .font_file = "fonts/Roboto-Regular.ttf",
        .text_file = "texts/react-dom.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "fonts/SourceSerifVariable-Roman.ttf",
        .text_file = "texts/react-dom.txt",
        .direction = "ltr",
    },
};

const retained_aots_parity_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
    no_positions: bool = false,
}{
    .{
        .font_file = "gpos2_1_next_glyph_f1.otf",
        .text = "\u{0012}\u{0012}\u{0012}\u{0012}",
    },
    .{
        .font_file = "gpos_context1_boundary_f2.otf",
        .text = "\u{0011}\u{0014}\u{0014}\u{0014}\u{0014}\u{0014}\u{0011}",
    },
    .{
        .font_file = "gpos_context1_next_glyph_f1.otf",
        .text = "\u{0011}\u{0014}\u{0014}\u{0014}\u{0014}\u{0014}\u{0011}",
    },
    .{
        .font_file = "gsub1_1_modulo_f1.otf",
        .text = "\u{0011}\u{0012}\u{0013}\u{0014}\u{0015}\u{0016}\u{0017}\u{0018}",
        .no_positions = true,
    },
};

const retained_aots_feature_range_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
    ranges: []const []const u8,
}{
    .{
        .font_file = "gsub3_1_simple_f1.otf",
        .text = "\u{0011}\u{0012}\u{0011}\u{0012}\u{0011}\u{0012}\u{0011}\u{0012}\u{0011}\u{0012}\u{0011}\u{0012}\u{0011}",
        .ranges = &.{ "test=0:1:2", "test=1:3:4", "test=2:5:6", "test=3:7:8", "test=0:9:10", "test=1:11:12" },
    },
    .{
        .font_file = "gsub3_1_multiple_f1.otf",
        .text = "\u{0011}\u{0012}\u{0012}\u{0012}\u{0012}\u{0013}\u{0013}\u{0013}\u{0013}\u{0011}",
        .ranges = &.{ "test=0:1:2", "test=1:2:3", "test=2:3:4", "test=0:4:5", "test=0:5:6", "test=1:6:7", "test=2:7:8", "test=0:8:9" },
    },
    .{
        .font_file = "gsub3_1_lookupflag_f1.otf",
        .text = "\u{0011}\u{0012}\u{0012}\u{0012}\u{0013}\u{0013}\u{0013}\u{0013}\u{0011}",
        .ranges = &.{ "test=0:4:5", "test=1:5:6", "test=2:6:7", "test=0:7:8" },
    },
};

const retained_inline_harfbuzz_parity_gates = [_]struct {
    font_hash: []const u8,
    text: []const u8,
    direction: []const u8,
    script: ?[]const u8 = null,
    language: ?[]const u8 = null,
    enable_feature: ?[]const u8 = null,
    enable_feature_2: ?[]const u8 = null,
    disable_feature: ?[]const u8 = null,
    variation: ?[]const u8 = null,
    not_found_variation_selector_glyph: ?[]const u8 = null,
    font_ext: []const u8 = "ttf",
    face_index: ?[]const u8 = null,
    show_extents: bool = false,
    text_before: ?[]const u8 = null,
    text_after: ?[]const u8 = null,
    bot: bool = false,
    known_current_harfbuzz_difference: bool = false,
}{
    .{
        .font_hash = "65d1b9099cfb3191931d8d6112d7a03d979d579f",
        .text = "\u{00b2}\u{0b95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "932ad5132c2761297c74e9976fe25b08e5ffa10b",
        .text = "ড় ঢ় ড় ঢ়",
        .direction = "ltr",
    },
    .{
        .font_hash = "932ad5132c2761297c74e9976fe25b08e5ffa10b",
        .text = "\u{09dc} \u{09dd} \u{09a1}\u{09bc} \u{09a2}\u{09bc}",
        .direction = "ltr",
    },
    .{
        .font_hash = "49c9f7485c1392fa09a1b801bc2ffea79275f22e",
        .text = "VABEabcd",
        .direction = "ltr",
    },
    .{
        .font_hash = "21b7fb9c1eeae260473809fbc1fe330f66a507cd",
        .text = "ىِٕ",
        .direction = "rtl",
    },
    .{
        .font_hash = "21b7fb9c1eeae260473809fbc1fe330f66a507cd",
        .text = "ىٕ͏ِ",
        .direction = "rtl",
    },
    .{
        .font_hash = "fcea341ba6489536390384d8403ce5287ba71a4a",
        .text = "ه‍",
        .direction = "ltr",
    },
    .{
        .font_hash = "6677074106f94a2644da6aaaacd5bbd48cbdc7de",
        .text = "ه‍",
        .direction = "ltr",
    },
    .{
        .font_hash = "08b4b136f418add748dc641eb4a83033476f1170",
        .text = "ه‍",
        .direction = "ltr",
    },
    .{
        .font_hash = "051d92f8bc6ff724511b296c27623f824de256e9",
        .text = "u͡͏́i",
        .direction = "ltr",
    },
    .{
        .font_hash = "bf962d3202883a820aed019d9b5c1838c2ff69c6",
        .text = " یَ͏ّ",
        .direction = "ltr",
        .script = "arab",
    },
    .{
        .font_hash = "cee442574141a0304e780b27dd872519f7d229db",
        .text = "صِ͏ّا",
        .direction = "ltr",
        .script = "arab",
    },
    .{
        .font_hash = "21b7fb9c1eeae260473809fbc1fe330f66a507cd",
        .text = "ىٕ͏ِ",
        .direction = "ltr",
    },
    .{
        .font_hash = "24b8d24d00ae86f49791b746da4c9d3f717a51a8",
        .text = "\u{0628}\u{0618}\u{0619}\u{064e}\u{064f}\u{0654}\u{0658}\u{0653}\u{0654}\u{0651}\u{0656}\u{0651}\u{065c}\u{0655}\u{0650}",
        .direction = "ltr",
    },
    .{
        .font_hash = "813c2f8e5512187fd982417a7fb4286728e6f4a8",
        .text = "\u{1820}\u{180b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "8a9fea2a7384f2116e5b84a9b31f83be7850ce21",
        .text = "\u{1820}\u{180b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "a919b33197965846f21074b24e30250d67277bce",
        .text = "لله",
        .direction = "rtl",
    },
    .{
        .font_hash = "bf39b0e91ef9807f15a9e283a21a14a209fd2cfc",
        .text = "لَٰٓئ",
        .direction = "rtl",
    },
    .{
        .font_hash = "94a5d6fb15a27521fba9ea4aee9cb39b2d03322a",
        .text = "\u{064a}\u{064e}\u{0670}\u{0653}\u{0640}\u{0654}\u{064e}\u{0627}",
        .direction = "ltr",
    },
    .{
        .font_hash = "21b7fb9c1eeae260473809fbc1fe330f66a507cd",
        .text = "ىِٕ",
        .direction = "ltr",
    },
    .{
        .font_hash = "21b7fb9c1eeae260473809fbc1fe330f66a507cd",
        .text = "ىِٕ",
        .direction = "ltr",
    },
    .{
        .font_hash = "21b7fb9c1eeae260473809fbc1fe330f66a507cd",
        .text = "ىِ͏ٕ",
        .direction = "ltr",
    },
    .{
        .font_hash = "507637795ce4f2975593da54d12b46f76c7cc4cc",
        .text = "࢑١٢٣٤٫",
        .direction = "ltr",
    },
    .{
        .font_hash = "507637795ce4f2975593da54d12b46f76c7cc4cc",
        .text = "١٢٣࢑٤٫",
        .direction = "ltr",
    },
    .{
        .font_hash = "d9b8bc10985f24796826c29f7ccba3d0ae11ec02",
        .text = "ܘ\u{070f}ܘܘ.",
        .direction = "rtl",
    },
    .{
        .font_hash = "ee39587d13b2afa5499cc79e45780aa79293bbd4",
        .text = "\u{1f42f}",
        .direction = "ltr",
        .show_extents = true,
    },
    .{
        .font_hash = "fcbaa518d3cce441ed37ae3b1fed6a19e9b54efd",
        .text = "\u{1f600}",
        .direction = "ltr",
        .show_extents = true,
    },
    .{
        .font_hash = "ab14b4eb9d7a67e293f51d30d719add06c9d6e06",
        .text = "\u{1000}\u{103a}\u{1004}\u{1037}\u{1039}\u{1041}",
        .direction = "ltr",
        .script = "Qaag",
    },
    .{
        .font_hash = "af3086380b743099c54a3b11b96766039ea62fcd",
        .text = "\u{101d}\u{fe00}\u{1031}\u{fe00}\u{1031}\u{fe00}",
        .direction = "ltr",
    },
    .{
        .font_hash = "f4ba5a767ef56a40133844507efb98fee5635e71",
        .text = "\u{1000}\u{1032}\u{1038}\u{1069}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a3d8f381387dd29be1e897e4b5100ac8b4829e1",
        .text = "বেবে",
        .direction = "ltr",
    },
    .{
        .font_hash = "49bd922bd447fb15bb05abab5c7ceac8d547a3a2",
        .text = "\u{0995}\u{09be}\u{09b9}\u{09bf}\u{09a8}\u{09c0}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1c2fb74c1b2aa173262734c1f616148f1648cfd6",
        .text = "\u{0995}\u{09cd}\u{0995} \u{0995}\u{09cd}\u{09b0}\u{0995}\u{09cd}\u{09b2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1c2fb74c1b2aa173262734c1f616148f1648cfd6",
        .text = "\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995}\u{0995}\u{09cd}\u{0995} \u{0995}\u{09cd}\u{09b0}\u{0995}\u{09cd}\u{09b2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "d629e7fedc0b350222d7987345fe61613fa3929a",
        .text = "\u{0915}\u{093f}\u{0915}\u{093f}",
        .direction = "ltr",
    },
    .{
        .font_hash = "f499fbc23865022234775c43503bba2e63978fe1",
        .text = "\u{09b0}\u{09cd}\u{09a5}\u{09cd}\u{09af}\u{09c0}",
        .direction = "ltr",
    },
    .{
        .font_hash = "226bc2deab3846f1a682085f70c67d0421014144",
        .text = "യ്രെ",
        .direction = "ltr",
    },
    .{
        .font_hash = "e207635780b42f898d58654b65098763e340f5c7",
        .text = "യ്രെ",
        .direction = "ltr",
    },
    .{
        .font_hash = "c825900b8a5b6571f0eb6c8c25c6512880bc42e9",
        .text = "\u{0d15}\u{0d4d}\u{0d2f}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d15}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d15}\u{0d4d}\u{0d15}\u{0d4d}\u{0d30}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d28}\u{0d4d}\u{0d28}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d17}\u{0d4d}\u{0d17}\u{0d4d}\u{0d30}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d17}\u{0d4d}\u{0d30}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d17}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d17}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d17}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d17}\u{0d4d}\u{0d17}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d17}\u{0d4d}\u{0d17}\u{0d4d}\u{0d30}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d17}\u{0d4d}\u{0d17}\u{0d4d}\u{0d30}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d17}\u{0d4d}\u{0d17}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d17}\u{0d4d}\u{0d30}\u{0d4b}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d15}\u{0d41}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d15}\u{0d4d}\u{0d15}\u{0d41}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55e2910dbc9ef5dd89f4e146e7e0152169545b6a",
        .text = "\u{0d4e}\u{0d1a}\u{0d4d}\u{0d1a}\u{0d4d}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1735326da89f0818cd8c51a0600e9789812c0f94",
        .text = "\u{0a51}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1735326da89f0818cd8c51a0600e9789812c0f94",
        .text = "\u{25cc}\u{0a51}",
        .direction = "ltr",
    },
    .{
        .font_hash = "85fe0be440c64ac77699e21c2f1bd933a919167e",
        .text = "\u{0a15}\u{0a51}\u{0a47}",
        .direction = "ltr",
    },
    .{
        .font_hash = "f75c4b05a0a4d67c1a808081ae3d74a9c66509e8",
        .text = "\u{0a20}\u{0a75}\u{0a47}",
        .direction = "ltr",
    },
    .{
        .font_hash = "f75c4b05a0a4d67c1a808081ae3d74a9c66509e8",
        .text = "\u{0a20}\u{0a75}\u{0a42}",
        .direction = "ltr",
    },
    .{
        .font_hash = "3cae6bfe5b57c07ba81ddbd54c02fe4f3a1e3bf6",
        .text = "\u{0cb0}\u{0ccd}\u{0c95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "a014549f766436cf55b2ceb40e462038938ee899",
        .text = "\u{0cf1}\u{0c95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55c88ebbe938680b08f92c3de20713183e0c7481",
        .text = "\u{0cf2}\u{0caa}",
        .direction = "ltr",
    },
    .{
        .font_hash = "341421e629668b1a1242245d39238ca48432d35d",
        .text = "\u{0cf1}",
        .direction = "ltr",
    },
    .{
        .font_hash = "663aef6b019dbf45ffd74089e2b5f2496ceceb18",
        .text = "\u{0cf2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "4fbf14f4f51c21480971aa9ea81c229660924caa",
        .text = "\u{1cf5}\u{0915}",
        .direction = "ltr",
    },
    .{
        .font_hash = "3cae6bfe5b57c07ba81ddbd54c02fe4f3a1e3bf6",
        .text = "\u{0cb0}\u{200d}\u{0ccd}\u{0c95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "3cae6bfe5b57c07ba81ddbd54c02fe4f3a1e3bf6",
        .text = "\u{0cb0}\u{0ccd}\u{200d}\u{0c95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a5face3fcbd929d228235c2f72bbd6f8eb37424",
        .text = "\u{0904} \u{0905}\u{0946}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a5face3fcbd929d228235c2f72bbd6f8eb37424",
        .text = "\u{0906} \u{0905}\u{093e}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a5face3fcbd929d228235c2f72bbd6f8eb37424",
        .text = "\u{0908} \u{0930}\u{094d}\u{0907}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a5face3fcbd929d228235c2f72bbd6f8eb37424",
        .text = "\u{090a} \u{0909}\u{0941}",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a5face3fcbd929d228235c2f72bbd6f8eb37424",
        .text = "\u{090d} \u{090f}\u{0945}",
        .direction = "ltr",
    },
    .{
        .font_hash = "41071178fbce4956d151f50967af458dbf555f7b",
        .text = "\u{0926}\u{093f}\u{0938}\u{0902}\u{092c}\u{0930}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a86} \u{0a85}\u{0abe}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a8d} \u{0a85}\u{0ac5}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a8f} \u{0a85}\u{0ac7}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a90} \u{0a85}\u{0ac8}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a91} \u{0a85}\u{0ac9}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a93} \u{0a85}\u{0abe}\u{0ac5}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0a94} \u{0a85}\u{0abe}\u{0ac8}",
        .direction = "ltr",
    },
    .{
        .font_hash = "738d9f3b8c2dfd03875bf35a61d28fd78faf17c8",
        .text = "\u{0ac9} \u{0ac5}\u{0abe}",
        .direction = "ltr",
    },
    .{
        .font_hash = "757ebd573617a24aa9dfbf0b885c54875c6fe06b",
        .text = "\u{115f}\u{11a2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "7e14e7883ed152baa158b80e207b66114c823a8b",
        .text = "\u{11a2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "600387433d01cd5799e421dad6510a54c862f56b",
        .text = "\u{ac00}=>",
        .direction = "ltr",
    },
    .{
        .font_hash = "600387433d01cd5799e421dad6510a54c862f56b",
        .text = "\u{ac00}\u{b098}",
        .direction = "ltr",
    },
    .{
        .font_hash = "600387433d01cd5799e421dad6510a54c862f56b",
        .text = "\u{1100}\u{1100}",
        .direction = "ltr",
    },
    .{
        .font_hash = "600387433d01cd5799e421dad6510a54c862f56b",
        .text = "\u{b098}\u{b098}",
        .direction = "ltr",
    },
    .{
        .font_hash = "600387433d01cd5799e421dad6510a54c862f56b",
        .text = "\u{ac00}=>",
        .direction = "ltr",
        .enable_feature = "calt=0",
    },
    .{
        .font_hash = "81c368a33816fb20e9f647e8f24e2180f4720263",
        .text = "\u{0c80}\u{0c82}",
        .direction = "ltr",
    },
    .{
        .font_hash = "3d0b77a2360aa6faa1385aaa510509ab70dfbeff",
        .text = "\u{0cf1}",
        .direction = "ltr",
    },
    .{
        .font_hash = "3d0b77a2360aa6faa1385aaa510509ab70dfbeff",
        .text = "\u{0cf2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "57a9d9f83020155cbb1d2be1f43d82388cbecc88",
        .text = "\u{0c9a}\u{0ccd}\u{0c9a}\u{0ccd}",
        .direction = "ltr",
    },
    .{
        .font_hash = "e716f6bd00a108d186b7e9f47b4515565f784f36",
        .text = "\u{0c1a}\u{0c3f}\u{0c32}\u{0c4d}\u{0c15}\u{0c42}\u{0c30}\u{0c4d}",
        .direction = "ltr",
    },
    .{
        .font_hash = "54674a3111d209fb6be0ed31745314b7a8d2c244",
        .text = "\u{0ba4}\u{0bcd}\u{00b3}",
        .direction = "ltr",
    },
    .{
        .font_hash = "190a621e48d4af1fffd8144bd41d2027e9a32fbf",
        .text = "\u{0b95}\u{0bc1}",
        .direction = "ltr",
        .enable_feature = "ss03",
    },
    .{
        .font_hash = "e2b17207c4b7ad78d843e1b0c4d00b09398a1137",
        .text = "\u{0baa}\u{0baa}\u{0bcd}",
        .direction = "ltr",
    },
    .{
        .font_hash = "b151cfcdaa77585d77f17a42158e0873fc8e2633",
        .text = "\u{0baa}\u{11301}\u{11303}",
        .direction = "ltr",
    },
    .{
        .font_hash = "3493e92eaded2661cadde752a39f9d58b11f0326",
        .text = "\u{0ba4}\u{0bc6}\u{1133c}\u{0baa}\u{1133c}\u{0bc6}\u{1133c}",
        .direction = "ltr",
    },
    .{
        .font_hash = "d23d76ea0909c14972796937ba072b5a40c1e257",
        .text = "r",
        .direction = "ltr",
        .variation = "0,0.65,0",
    },
    .{
        .font_hash = "d23d76ea0909c14972796937ba072b5a40c1e257",
        .text = "r",
        .direction = "ltr",
        .variation = "0,0.7,0",
    },
    .{
        .font_hash = "82f4f3b57bb55344e72e70231380202a52af5805",
        .text = "ཨི",
        .direction = "ltr",
    },
    .{
        .font_hash = "82f4f3b57bb55344e72e70231380202a52af5805",
        .text = "ཨཿ",
        .direction = "ltr",
    },
    .{
        .font_hash = "b895f8ff06493cc893ec44de380690ca0074edfa",
        .text = "הֲבֵל",
        .direction = "rtl",
    },
    .{
        .font_hash = "b895f8ff06493cc893ec44de380690ca0074edfa",
        .text = "קֹהֶלֶת",
        .direction = "rtl",
    },
    .{
        .font_hash = "f22416c692720a7d46fadf4af99f4c9e094f00b9",
        .text = "تختة",
        .direction = "rtl",
    },
    .{
        .font_hash = "f22416c692720a7d46fadf4af99f4c9e094f00b9",
        .text = "تخنة",
        .direction = "rtl",
    },
    .{
        .font_hash = "f22416c692720a7d46fadf4af99f4c9e094f00b9",
        .text = "تخئة",
        .direction = "rtl",
    },
    .{
        .font_hash = "f22416c692720a7d46fadf4af99f4c9e094f00b9",
        .text = "تخثة",
        .direction = "rtl",
    },
    .{
        .font_hash = "f22416c692720a7d46fadf4af99f4c9e094f00b9",
        .text = "تخٹة",
        .direction = "rtl",
    },
    .{
        .font_hash = "NotoNastaliqUrdu-Regular",
        .text = "ببے",
        .direction = "rtl",
    },
    .{
        .font_hash = "NotoNastaliqUrdu-Regular",
        .text = "بببے",
        .direction = "rtl",
    },
    .{
        .font_hash = "NotoNastaliqUrdu-Regular",
        .text = "ببببے",
        .direction = "rtl",
    },
    .{
        .font_hash = "NotoNastaliqUrdu-Regular",
        .text = "بببببے",
        .direction = "rtl",
    },
    .{
        .font_hash = "e39391c77a6321c2ac7a2d644de0396470cd4bfe",
        .text = "abcdefghijklmnop",
        .direction = "ltr",
    },
    .{
        .font_hash = "e39391c77a6321c2ac7a2d644de0396470cd4bfe",
        .text = "ckckck",
        .direction = "ltr",
    },
    .{
        .font_hash = "e39391c77a6321c2ac7a2d644de0396470cd4bfe",
        .text = "AV",
        .direction = "ltr",
    },
    .{
        .font_hash = "bbc24004e776f348a0f72287d24b0124867ee750",
        .text = "f︀i",
        .direction = "ltr",
        .not_found_variation_selector_glyph = "1000000",
    },
    .{
        .font_hash = "8228d035fcd65d62ec9728fb34f42c63be93a5d3",
        .text = "x́X́",
        .direction = "ltr",
    },
    .{
        .font_hash = "73e84dac2fc6a2d1bc9250d1414353661088937d",
        .text = "\u{10300}\u{10301}",
        .direction = "ltr",
    },
    .{
        .font_hash = "73e84dac2fc6a2d1bc9250d1414353661088937d",
        .text = "\u{10300}\u{10301}",
        .direction = "rtl",
    },
    .{
        .font_hash = "856ff9562451293cbeff6f396d4e3877c4f0a436",
        .text = "a͜b",
        .direction = "ltr",
    },
    .{
        .font_hash = "15dfc433a135a658b9f4b1a861b5cdd9658ccbb9",
        .text = "123⁄456",
        .direction = "ltr",
    },
    .{
        .font_hash = "15dfc433a135a658b9f4b1a861b5cdd9658ccbb9",
        .text = "١٢٣⁄٤٥٦",
        .direction = "ltr",
    },
    .{
        .font_hash = "15dfc433a135a658b9f4b1a861b5cdd9658ccbb9",
        .text = "123⁄",
        .direction = "ltr",
    },
    .{
        .font_hash = "15dfc433a135a658b9f4b1a861b5cdd9658ccbb9",
        .text = "١٢٣⁄",
        .direction = "ltr",
    },
    .{
        .font_hash = "15dfc433a135a658b9f4b1a861b5cdd9658ccbb9",
        .text = "⁄456",
        .direction = "ltr",
    },
    .{
        .font_hash = "15dfc433a135a658b9f4b1a861b5cdd9658ccbb9",
        .text = "⁄٤٥٦",
        .direction = "ltr",
    },
    .{
        .font_hash = "1c04a16f32a39c26c851b7fc014d2e8d298ba2b8",
        .text = "‐",
        .direction = "ltr",
    },
    .{
        .font_hash = "1c04a16f32a39c26c851b7fc014d2e8d298ba2b8",
        .text = "‑",
        .direction = "ltr",
    },
    .{
        .font_hash = "96fcf8dc57095c3d89f69b0f74f0d802c213f4da",
        .text = "..",
        .direction = "ltr",
    },
    .{
        .font_hash = "8a312e38b9b90183ef154a0c2ab92a9def6cb82f",
        .text = "..",
        .direction = "ltr",
    },
    .{
        .font_hash = "b121d4306b2e3add5abbaad21d95fcf04aacbd64",
        .text = "ACAB",
        .direction = "ltr",
    },
    .{
        .font_hash = "45855bc8d46332b39c4ab9e2ee1a26b1f896da6b",
        .text = "กิก",
        .direction = "ltr",
    },
    .{
        .font_hash = "7a37dc4d5bf018456aea291cee06daf004c0221c",
        .text = "กิก",
        .direction = "ltr",
    },
    .{
        .font_hash = "bb0c53752e85c3d28973ebc913287b8987d3dfe8",
        .text = "กิก",
        .direction = "ltr",
    },
    .{
        .font_hash = "63a539a90a371ccf028dc2dcced9b63b07163be7",
        .text = "\u{0e81}\u{0ece}\u{0ecd}\u{0eb2}",
        .direction = "ltr",
    },
    .{
        .font_hash = "a04cc6365876308945033b2a49f54afe899e7bf8",
        .text = "..",
        .direction = "ltr",
    },
    .{
        .font_hash = "a04cc6365876308945033b2a49f54afe899e7bf8",
        .text = "..",
        .direction = "ltr",
        .script = "deva",
    },
    .{
        .font_hash = "e5ff44940364c2247abed50bdda30d2ef5aedfe4",
        .text = "١٢٨٣٧",
        .direction = "ltr",
        .script = "arab",
        .enable_feature = "pnum",
    },
    .{
        .font_hash = "a6b17da98b9f1565ba428719777bbf94a66403c1",
        .text = "۝١٢٣",
        .direction = "ltr",
        .script = "arab",
    },
    .{
        .font_hash = "b082211be29a3e2cf91f0fd43497e40b2a27b344",
        .text = "۝١٢ب",
        .direction = "ltr",
        .script = "arab",
    },
    .{
        .font_hash = "3b791518a9ba89675df02f1eefbc9026a50648a6",
        .text = "۝١٢٣",
        .direction = "ltr",
        .script = "arab",
    },
    .{
        .font_hash = "3b791518a9ba89675df02f1eefbc9026a50648a6",
        .text = "۝١٢٣",
        .direction = "rtl",
        .script = "arab",
    },
    .{
        .font_hash = "3f24aff8b768e586162e9b9d03b15c36508dd2ae",
        .text = "صلطخلطج",
        .direction = "rtl",
        .enable_feature = "salt=2",
    },
    .{
        .font_hash = "a706511c65fb278fda87eaf2180ca6684a80f423",
        .text = "A AB",
        .direction = "ltr",
    },
    .{
        .font_hash = "1b66a1f4b076b734caa6397b3e57231af1feaafb",
        .text = "1234567890⁄1234567890",
        .direction = "ltr",
    },
    .{
        .font_hash = "8339c821814d9bad7c77169332327ad8b0f33c81",
        .text = "\u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627}",
        .direction = "ltr",
    },
    .{
        .font_hash = "5bb74492f5e0ffa1fbb72e4c881be035120b6513",
        .text = "TUV",
        .direction = "ltr",
        .enable_feature = "rand=0",
    },
    .{
        .font_hash = "5bb74492f5e0ffa1fbb72e4c881be035120b6513",
        .text = "TUV",
        .direction = "ltr",
        .enable_feature = "rand=2",
    },
    .{
        .font_hash = "5bb74492f5e0ffa1fbb72e4c881be035120b6513",
        .text = "TUVTUVTUVTUV",
        .direction = "ltr",
    },
    .{
        .font_hash = "be10ea33f28a139f3305db2302af6220f2f9a583",
        .text = ".\u{1bc36}\u{1bc36}\u{1bc36}\u{1bc36}",
        .direction = "ltr",
        .enable_feature = "rtl1",
        .enable_feature_2 = "ltr2",
    },
    .{
        .font_hash = "4cce528e99f600ed9c25a2b69e32eb94a03b4ae8",
        .text = "\u{1a48}\u{1a58}\u{1a25}\u{1a48}\u{1a58}\u{1a25}\u{1a6e}\u{1a63}",
        .direction = "ltr",
    },
    .{
        .font_hash = "5bbf3712e6f79775c66a4407837a90e591efbef2",
        .text = "\u{1f1fa}\u{1f1fc}",
        .direction = "ltr",
    },
    .{
        .font_hash = "bef923f4ccb474f961c43b63a9c74b7d9b7a023f",
        .text = "a...",
        .direction = "ltr",
    },
    .{
        .font_hash = "53a91c20e33a596f2be17fb68b382d6b7eb85d5c",
        .text = "AV",
        .direction = "ltr",
    },
    .{
        .font_hash = "f79eb71df4e4c9c273b67b89a06e5ff9e3c1f834",
        .text = "m\u{0315}",
        .direction = "ltr",
    },
    .{
        .font_hash = "ea3f63620511b2097200d23774ffef197e829e69",
        .text = "y\u{0325}",
        .direction = "ltr",
    },
    .{
        .font_hash = "c4e48b0886ef460f532fb49f00047ec92c432ec0",
        .text = "كممثل",
        .direction = "rtl",
    },
    .{
        .font_hash = "298c9e1d955f10f6f72c6915c3c6ff9bf9695cec",
        .text = "كممثل",
        .direction = "rtl",
    },
    .{
        .font_hash = "98b7887cff91f722b92a8ff800120954606354f9",
        .text = "\u{100f}\u{103c}\u{102f}\u{1036}",
        .direction = "ltr",
    },
    .{
        .font_hash = "55db4d5539b0f7f0b5e6cdb3ce6dd1eab6b3392a",
        .text = "\u{066e}\u{064e}\u{0644}\u{064e}",
        .direction = "rtl",
    },
    .{
        .font_hash = "55db4d5539b0f7f0b5e6cdb3ce6dd1eab6b3392a",
        .text = "\u{066e}\u{064e}\u{0644}\u{064e}",
        .direction = "rtl",
        .disable_feature = "liga",
    },
    .{
        .font_hash = "73c3222a2992bac9067663888d2a1503774976bb",
        .text = "\u{0628}\u{064e}\u{0645}\u{064e}\u{0644}\u{064e}",
        .direction = "rtl",
    },
    .{
        .font_hash = "1af868501dfcfd16184116b966f7fb2bd310623c",
        .text = "\u{0628}\u{064e}\u{0644}\u{064e}\u{0647}\u{064e}",
        .direction = "rtl",
    },
    .{
        .font_hash = "5479969a7d35aabd6a39dcfacb88e36a8f42a7ac",
        .text = "\u{0628}\u{064e}\u{062a}\u{062d}",
        .direction = "rtl",
    },
    .{
        .font_hash = "d92da3f226c722c1c67353b2391b3472639f03f5",
        .text = "\u{0628}\u{064e}\u{062a}\u{062d}",
        .direction = "rtl",
    },
    .{
        .font_hash = "152825a19abd4a3094a41c9e4b4de5e2577dd1df",
        .text = "\u{0633}\u{064e}\u{06cc}\u{064e}\u{0642}\u{064f}\u{0648}\u{0652}\u{0644}\u{064f}  \u{0633}\u{064e}\u{0642}\u{064e}\u{0645}\u{064f}\u{0646}\u{064e}",
        .direction = "rtl",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{0650}\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}\u{0646}\u{064e}\u{0627}",
        .direction = "rtl",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}\u{0646}\u{064e}\u{0627}",
        .direction = "rtl",
        .text_before = "\u{0643}\u{0650}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}\u{0646}\u{064e}\u{0627}",
        .direction = "rtl",
        .text_before = "\u{0643}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{0650}\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_after = "\u{0646}\u{064e}\u{0627}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{0650}\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_after = "\u{0646}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_before = "\u{0643}\u{0650}",
        .text_after = "\u{0646}\u{064e}\u{0627}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_before = "\u{0643}",
        .text_after = "\u{0646}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{062a}\u{0628}",
        .direction = "rtl",
        .text_before = "\u{0627}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{062a}\u{0628}\u{0627}",
        .direction = "rtl",
        .text_after = "\u{0627}",
    },
    .{
        .font_hash = "3105b51976b879032c66aa93a634b3b3672cd344",
        .text = "\u{064e}",
        .direction = "rtl",
        .bot = true,
        // HarfBuzz 14.3 changed this BOT-only dotted-circle order. Retain the
        // Cangjie/HarfRust legacy contract below, but do not let this known
        // cross-version difference make the current-HarfBuzz umbrella red.
        .known_current_harfbuzz_difference = true,
    },
    .{
        .font_hash = "3105b51976b879032c66aa93a634b3b3672cd344",
        .text = "\u{064e}",
        .direction = "rtl",
        .text_before = "\u{0627}",
        .bot = true,
    },
    .{
        .font_hash = "065b01e54f35f0d849fd43bd5b936212739a50cb",
        .text = "\u{101a}\u{1035}",
        .direction = "ltr",
    },
    .{
        .font_hash = "a232bb734d4c6c898a44506547d19768f0eba6a6",
        .text = "\u{1000}\u{1031}\u{1084}",
        .direction = "ltr",
    },
    .{
        .font_hash = "65d1b9099cfb3191931d8d6112d7a03d979d579f",
        .text = "\u{00b2}\u{1000}",
        .direction = "ltr",
    },
    .{
        .font_hash = "65d1b9099cfb3191931d8d6112d7a03d979d579f",
        .text = "\u{00b2}\u{0b95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "d3129450fafe5e5c98cfc25a4e71809b1b4d2855",
        .text = "|",
        .direction = "ltr",
        .language = "dv",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "fa",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "ja",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-cn",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-sg",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-tw",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-hans",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-hant",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-hant-hk",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zhh",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-HK",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-mo",
    },
    .{
        .font_hash = "6991b13ce889466be6de3f66e891de2bc0f117ee",
        .text = "J",
        .direction = "ltr",
        .language = "zh-Hant-mo",
    },
    .{
        .font_hash = "63a539a90a371ccf028dc2dcced9b63b07163be7",
        .text = "กัำ",
        .direction = "ltr",
    },
    .{
        .font_hash = "63a539a90a371ccf028dc2dcced9b63b07163be7",
        .text = "ກັຳ",
        .direction = "ltr",
    },
    .{
        .font_hash = "FallbackPlus-Javanese-no-GDEF",
        .font_ext = "otf",
        .text = "\u{a995}\u{a9bf}",
        .direction = "ltr",
    },
    .{
        .font_hash = "755160ddba002332349fda3eb999e629d63dccf6",
        .text = "\u{0a2d}\u{0a4d}\u{0a30}\u{0a42}",
        .direction = "ltr",
    },
    .{
        .font_hash = "5028afb650b1bb718ed2131e872fbcce57828fff",
        .text = "\u{0b13}\u{200d}\u{0b01}",
        .direction = "ltr",
    },
    .{
        .font_hash = "5028afb650b1bb718ed2131e872fbcce57828fff",
        .text = "\u{0b13}\u{200c}\u{0b01}",
        .direction = "ltr",
    },
    .{
        .font_hash = "b3075ca42b27dde7341c2d0ae16703c5b6640df0",
        .text = "\u{0b2c}\u{0b55}\u{0b3e}",
        .direction = "ltr",
    },
    .{
        .font_hash = "b3075ca42b27dde7341c2d0ae16703c5b6640df0",
        .text = "\u{0b2c}\u{0b3e}\u{0b55}",
        .direction = "ltr",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .font_ext = "otf",
        .text = "AB",
        .direction = "ttb",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .font_ext = "otf",
        .text = "AB",
        .direction = "ttb",
        .variation = "wght=700",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .font_ext = "ttf",
        .text = "AB",
        .direction = "ttb",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .font_ext = "ttf",
        .text = "AB",
        .direction = "ttb",
        .variation = "wght=700",
    },
    .{
        .font_hash = "2681c1c72d6484ed3410417f521b1b819b4e2392",
        .text = "\u{3008}",
        .direction = "ttb",
    },
    .{
        .font_hash = "2681c1c72d6484ed3410417f521b1b819b4e2392",
        .text = "\u{3008}",
        .direction = "btt",
    },
    .{
        .font_hash = "2681c1c72d6484ed3410417f521b1b819b4e2392",
        .text = "\u{3008}",
        .direction = "rtl",
    },
    .{
        .font_hash = "191826b9643e3f124d865d617ae609db6a2ce203",
        .text = "\u{300c}",
        .direction = "ttb",
    },
    .{
        .font_hash = "5af5361ed4d1e8305780b100e1730cb09132f8d1",
        .text = "\u{0dbb}\u{0dca}\u{200d}\u{0dba}\u{0dca}\u{200d}\u{0dba}",
        .direction = "ltr",
    },
    .{
        .font_hash = "df768b9c257e0c9c35786c47cae15c46571d56be",
        .text = "\u{0633}\u{064f}\u{0644}\u{064a}\u{0651}\u{064e}\u{0627}\u{0645}\u{062a}\u{064a}",
        .direction = "ltr",
    },
    .{
        .font_hash = "872d2955d326bd6676a06f66b8238ebbaabc212f",
        .text = "\u{0628}\u{0628}\u{0628}",
        .direction = "ltr",
    },
    .{
        .font_hash = "TTC",
        .font_ext = "ttc",
        .text = "\u{2026} \u{002e}",
        .direction = "ltr",
        .face_index = "0",
    },
    .{
        .font_hash = "TTC",
        .font_ext = "ttc",
        .text = "\u{2026} \u{002e}",
        .direction = "ltr",
        .face_index = "1",
    },
    .{
        .font_hash = "DFONT",
        .font_ext = "dfont",
        .text = "\u{2026} \u{002e}",
        .direction = "ltr",
        .face_index = "0",
    },
};

const retained_harfbuzz_text_parity_gates = [_]struct {
    font_hash: []const u8,
    text_file: []const u8,
    direction: []const u8,
}{
    .{
        .font_hash = "1c2c3fc37b2d4c3cb2ef726c6cdaaabd4b7f3eb9",
        .text_file = "tests/data/spaces-horizontal.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "1c2c3fc37b2d4c3cb2ef726c6cdaaabd4b7f3eb9",
        .text_file = "tests/data/spaces-horizontal.txt",
        .direction = "ttb",
    },
    .{
        .font_hash = "f4ba5a767ef56a40133844507efb98fee5635e71",
        .text_file = "tests/data/myanmar-syllable-machine-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "8116e5d8fedfbec74e45dc350d2416d810bed8c4",
        .text_file = "tests/data/devanagari-indic-joiners-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "3998336402905b8be8301ef7f47cf7e050cbb1bd",
        .text_file = "tests/data/khmer-mark-cross-offset-tests.txt",
        .direction = "ltr",
    },
    // These four corpus files retain all 19 rows from HarfBuzz's in-house
    // `mongolian-variation-selector.tests`, grouped by font so the parity gate
    // parses each production fixture only once.
    .{
        .font_hash = "37033cc5cf37bb223d7355153016b6ccece93b28",
        .text_file = "tests/data/mongolian-variation-selector/37033cc5cf37bb223d7355153016b6ccece93b28.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "ef86fe710cfea877bbe0dbb6946a1f88d0661031",
        .text_file = "tests/data/mongolian-variation-selector/ef86fe710cfea877bbe0dbb6946a1f88d0661031.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "a34a7b00f22ffb5fd7eef6933b81c7e71bc2cdfb",
        .text_file = "tests/data/mongolian-variation-selector/a34a7b00f22ffb5fd7eef6933b81c7e71bc2cdfb.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "4d4206e30b2dbf1c1ef492a8eae1c9e7829ebad8",
        .text_file = "tests/data/mongolian-variation-selector/4d4206e30b2dbf1c1ef492a8eae1c9e7829ebad8.txt",
        .direction = "ltr",
    },
};

const retained_myanmar_text_parity_gates = [_]struct {
    font_hash: []const u8,
    text_file: []const u8,
}{
    .{
        .font_hash = "065b01e54f35f0d849fd43bd5b936212739a50cb",
        .text_file = "tests/data/myanmar/misc-065b.txt",
    },
    .{
        .font_hash = "a232bb734d4c6c898a44506547d19768f0eba6a6",
        .text_file = "tests/data/myanmar/misc-a232.txt",
    },
    .{
        .font_hash = "af3086380b743099c54a3b11b96766039ea62fcd",
        .text_file = "tests/data/myanmar/syllable-af30.txt",
    },
    .{
        .font_hash = "f4ba5a767ef56a40133844507efb98fee5635e71",
        .text_file = "tests/data/myanmar/syllable-f4ba.txt",
    },
    .{
        .font_hash = "65d1b9099cfb3191931d8d6112d7a03d979d579f",
        .text_file = "tests/data/myanmar/syllable-65d1.txt",
    },
};

const retained_text_rendering_parity_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8,
    size: ?[]const u8 = null,
    remove_default_ignorables: bool = false,
}{
    .{
        .font_file = "NotoSansBalinese-Regular.ttf",
        .text_file = "tests/data/balinese-rendering-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "TestShapeLana.ttf",
        .text_file = "tests/data/tai-tham-rendering-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "TestShapeAran.ttf",
        .text_file = "tests/data/sharan-rendering-tests.txt",
        .direction = "rtl",
    },
    .{
        .font_file = "TestGSUBOne.otf",
        .text_file = "tests/data/gsub-1-rendering-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestShapeEthi.ttf",
        .text_file = "tests/data/gsub-2-ethiopic-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestGPOSOne.ttf",
        .text_file = "tests/data/gpos-1-rendering-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "TestGPOSTwo.otf",
        .text_file = "tests/data/gpos-2-rendering-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "TestShapeEthi.ttf",
        .text_file = "tests/data/gpos-3-ethiopic-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "TestGPOSThree.ttf",
        .text_file = "tests/data/gpos-4-mark-stacking-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "TestKERNOne.otf",
        .text_file = "tests/data/kern-rendering-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestCMAP14.otf",
        .text_file = "tests/data/cmap-1-variation-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestCMAP14.otf",
        .text_file = "tests/data/cmap-2-variation-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestCMAP13.ttf",
        .text_file = "tests/data/cmap-4-last-resort-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "NotoSerifKannada-Regular.ttf",
        .text_file = "tests/data/kannada-shknda-1-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "NotoSansKannada-Regular.ttf",
        .text_file = "tests/data/kannada-shknda-2-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_file = "NotoSansKannada-Regular.ttf",
        .text_file = "tests/data/kannada-shknda-3-tests.txt",
        .direction = "ltr",
    },
};

const retained_text_rendering_expected_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8,
    size: []const u8,
    expected_checksum: []const u8,
    remove_default_ignorables: bool = false,
}{
    .{
        .font_file = "TestCMAPMacTurkish.ttf",
        .text_file = "tests/data/cmap-3-mac-turkish-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .expected_checksum = "9038f53721f4d38",
        .remove_default_ignorables = true,
    },
};

const retained_inline_text_rendering_parity_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
    direction: []const u8,
}{
    // The upstream row ends in U+0020. Keep it explicit rather than relying
    // on invisible trailing whitespace in the line-oriented corpus.
    .{
        .font_file = "NotoSansKannada-Regular.ttf",
        .text = "ಧೋಂ ",
        .direction = "ltr",
    },
};

const retained_vertical_text_rendering_parity_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
    size: ?[]const u8 = null,
    variation: ?[]const u8 = null,
    harfrust: bool = true,
}{
    .{ .font_file = "NotoSansCJK-VF.abc.otf", .text = "AB" },
    .{ .font_file = "NotoSansCJK-VF.abc.otf", .text = "AB", .variation = "wght=700" },
    .{ .font_file = "NotoSansCJK-VF.abc.ttf", .text = "AB" },
    .{ .font_file = "NotoSerifHK-subset.ttf", .text = "AB" },
    .{ .font_file = "NotoSansCJK-VF.abc.ttf", .text = "AB", .variation = "wght=700" },
    .{ .font_file = "NotoSerifHK-subset.ttf", .text = "AB", .variation = "wght=700" },
    .{ .font_file = "4cbbc461be066fccc611dcc634af6e8cb2705537.ttf", .text = "\u{ff38}" },
    .{ .font_file = "191826b9643e3f124d865d617ae609db6a2ce203.ttf", .text = "\u{300c}" },
    .{ .font_file = "f9b1dd4dcb515e757789a22cb4241107746fd3d0.ttf", .text = "AB" },
    .{ .font_file = "NotoSans-VF.abc.ttf", .text = "bc", .size = "2000" },
    .{ .font_file = "NotoSans-VF.abc.ttf", .text = "ab" },
    // HarfRust's fontations backend intentionally differs from the OpenType
    // and FreeType references for varied glyf fallback without vmtx.
    .{ .font_file = "NotoSans-VF.abc.ttf", .text = "ab", .variation = "wght=700", .harfrust = false },
};

const retained_variable_text_rendering_parity_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
    direction: []const u8,
    size: []const u8,
    variations: []const []const u8,
    remove_default_ignorables: bool = false,
    harfbuzz_extents: bool = false,
}{
    .{
        .font_file = "TestGPOSFour.ttf",
        .text = "\u{0634}\u{0652}",
        .direction = "rtl",
        .size = "1000",
        .variations = &.{ "wght=100", "wght=300", "wght=600", "wght=700", "wght=900" },
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestHVAROne.otf",
        .text = "ABC",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=0", "wght=200", "wght=400", "wght=600", "wght=800", "wght=1000" },
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestHVARTwo.ttf",
        .text = "AB",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=0", "wght=200", "wght=400", "wght=600", "wght=800", "wght=1000" },
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestCVARGVARTwo.ttf",
        .text = "hon",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=28,wdth=100,opsz=72", "wght=94,wdth=100,opsz=72", "wght=194,wdth=100,opsz=72" },
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestCVARGVAROne.ttf",
        .text = "hon",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=28,wdth=100,opsz=72", "wght=94,wdth=100,opsz=72", "wght=194,wdth=100,opsz=72" },
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestGVAROne.ttf",
        .text = "彌",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=300", "wght=350", "wght=400", "wght=450", "wght=500", "wght=550", "wght=600", "wght=650", "wght=700" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "TestGVARTwo.ttf",
        .text = "彌",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=300", "wght=350", "wght=400", "wght=450", "wght=500", "wght=550", "wght=600", "wght=650", "wght=700" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "TestGVARThree.ttf",
        .text = "彌",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=300", "wght=350", "wght=400", "wght=450", "wght=500", "wght=550", "wght=600", "wght=650", "wght=700" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "Zycon.ttf",
        .text = "🦎",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "M1=-1.0,T1=0.0", "M1=-0.8,T1=0.1", "M1=-0.6,T1=0.2", "M1=-0.4,T1=0.3", "M1=-0.2,T1=0.4", "M1=0.0,T1=0.5", "M1=0.2,T1=0.6", "M1=0.4,T1=0.7", "M1=0.6,T1=0.8", "M1=0.8,T1=0.9", "M1=1.0,T1=1.0" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "Zycon.ttf",
        .text = "🌝",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "M1=-1.0", "M1=-0.8", "M1=-0.6", "M1=-0.4", "M1=-0.2", "M1=0.0", "M1=0.2", "M1=0.4", "M1=0.6", "M1=0.8", "M1=1.0" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "Zycon.ttf",
        .text = "🐢",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "T1=0.0", "T1=0.1", "T1=0.2", "T1=0.3", "T1=0.4", "T1=0.5", "T1=0.6", "T1=0.7", "T1=0.8", "T1=0.9", "T1=1.0" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "TestGVARFour.ttf",
        .text = "OIO",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=150", "wght=200", "wght=250", "wght=300", "wght=350", "wght=400", "wght=450" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "TestGVAREight.ttf",
        .text = "H",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "HV=0.0", "HV=-0.2", "HV=-0.4", "HV=-0.6", "HV=-0.8", "HV=-1.0" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "TestGVARNine.ttf",
        .text = "A",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "TEST=-1.0", "TEST=-0.5", "TEST=0.0", "TEST=0.5", "TEST=0.6", "TEST=0.7", "TEST=0.8", "TEST=0.9", "TEST=0.944444", "TEST=1.0" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "TestAVAR.ttf",
        .text = "⨁",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "TEST=100", "TEST=150", "TEST=200", "TEST=250", "TEST=300", "TEST=350", "TEST=400", "TEST=450", "TEST=500", "TEST=550", "TEST=600", "TEST=650", "TEST=700", "TEST=750", "TEST=800", "TEST=850", "TEST=900" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
    .{
        .font_file = "AdobeVFPrototype-Subset.otf",
        .text = "$",
        .direction = "ltr",
        .size = "1000",
        .variations = &.{ "wght=100", "wght=200", "wght=300", "wght=400", "wght=500", "wght=600", "wght=700", "wght=800", "wght=900" },
        .remove_default_ignorables = true,
        .harfbuzz_extents = true,
    },
};

const retained_extents_text_rendering_parity_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8,
    size: []const u8,
    remove_default_ignorables: bool = false,
}{
    .{
        .font_file = "FDArrayTest257.otf",
        .text_file = "tests/data/cff-1-2-rendering-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "FDArrayTest65535.otf",
        .text_file = "tests/data/cff-1-2-rendering-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestCFFThree.otf",
        .text_file = "tests/data/cff-3-seac-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestGLYFOne.ttf",
        .text_file = "tests/data/glyf-1-compound-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestSFNTOne.otf",
        .text_file = "tests/data/sfnt-1-2-outline-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
    .{
        .font_file = "TestSFNTTwo.ttf",
        .text_file = "tests/data/sfnt-1-2-outline-tests.txt",
        .direction = "ltr",
        .size = "1000",
        .remove_default_ignorables = true,
    },
};

const retained_text_rendering_rejection_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
    direction: []const u8,
}{
    // GSUB-3 deliberately expands `o` through nine contextual MultipleSubst
    // lookups. Upstream marks the expected output as `*`: only bounded
    // termination is required.
    .{
        .font_file = "TestGSUBThree.ttf",
        .text = "lol",
        .direction = "ltr",
    },
};

const retained_harfrust_custom_parity_gates = [_]struct {
    font_file: []const u8,
    text: []const u8,
}{
    .{
        .font_file = "PT_Sans-Caption-Web-Regular.ttf",
        .text = "\u{1ea4}n",
    },
    .{
        .font_file = "AdobeBlank-Regular.ttf",
        .text = "\u{0f42}\u{0fb7}",
    },
    .{
        .font_file = "Rasa.subset1.otf",
        .text = "\u{0a93}\u{0abc}",
    },
    .{
        .font_file = "AdobeBlank-Regular.ttf",
        .text = "\u{104a}\u{102f}",
    },
    .{
        .font_file = "NotoSansMyanmarUI-Regular.subset1.otf",
        .text = "\u{1004}\u{103a}\u{1039}\u{1002}\u{101c}",
    },
    .{
        .font_file = "NotoSansSinhala.subset1.otf",
        .text = "\u{0dc1}\u{200d}\u{0dca}\u{200d}\u{0dbb}\u{0dd3}",
    },
    .{
        .font_file = "LaBelleAurore.ttf",
        .text = "ke\u{031d}",
    },
    .{
        .font_file = "Linefont.ttf",
        .text = "T\u{021f}",
    },
    .{
        .font_file = "Linefont.ttf",
        .text = "\u{021f}a",
    },
};

const retained_inline_harfrust_parity_gates = [_]struct {
    font_hash: []const u8,
    text: []const u8,
    direction: []const u8,
    script: ?[]const u8 = null,
    variation: ?[]const u8 = null,
    disable_feature: ?[]const u8 = null,
    text_before: ?[]const u8 = null,
    text_after: ?[]const u8 = null,
    size: ?[]const u8 = null,
    cluster_level: ?[]const u8 = null,
    no_positions: bool = false,
    bot: bool = false,
    font_ext: []const u8 = "ttf",
}{
    .{
        .font_hash = "65d1b9099cfb3191931d8d6112d7a03d979d579f",
        .text = "\u{00b2}\u{0b95}",
        .direction = "ltr",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .font_ext = "otf",
        .text = "AB",
        .direction = "ttb",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .font_ext = "otf",
        .text = "AB",
        .direction = "ttb",
        .variation = "wght=700",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .text = "AB",
        .direction = "ttb",
    },
    .{
        .font_hash = "NotoSansCJK-VF.abc",
        .text = "AB",
        .direction = "ttb",
        .variation = "wght=700",
    },
    .{
        .font_hash = "191826b9643e3f124d865d617ae609db6a2ce203",
        .text = "\u{300c}",
        .direction = "ttb",
    },
    .{
        .font_hash = "HBTest-VF",
        .text = "A",
        .direction = "ltr",
        .variation = "TEST=491",
    },
    .{
        .font_hash = "HBTest-VF",
        .text = "A",
        .direction = "ltr",
        .variation = "TEST=509",
    },
    .{
        .font_hash = "ab40c89624a6104e5d0a2308e448a989302f515b",
        .text = " ",
        .direction = "ltr",
        .variation = "wdth=60",
    },
    .{
        .font_hash = "ab40c89624a6104e5d0a2308e448a989302f515b",
        .text = " ",
        .direction = "ltr",
        .variation = "wdth=402",
    },
    .{
        .font_hash = "e8691822f6a705e3e9fb48a0405c645b1a036590",
        .text = ".e",
        .direction = "ltr",
        .variation = "0001=500",
    },
    .{
        .font_hash = "7bbd3175734d5d291e1c15271ec0cbb97b626ebf",
        .text = "ffif",
        .direction = "ltr",
        .disable_feature = "liga",
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = "x\u{030a}X\u{030a}",
        .direction = "ltr",
        .cluster_level = "3",
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = "x\u{030a}X\u{030a}",
        .direction = "ltr",
        .cluster_level = "2",
    },
    .{
        .font_hash = "43ef465752be9af900745f72fe29cb853a1401a5",
        .text = "\u{05d4}\u{05b7}\u{05e9}\u{05bc}\u{05c1}\u{05b8}\u{05de}\u{05b4}\u{05dd}",
        .direction = "rtl",
        .cluster_level = "1",
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e33}",
        .direction = "ltr",
        .cluster_level = "0",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e33}",
        .direction = "ltr",
        .cluster_level = "1",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e33}",
        .direction = "ltr",
        .cluster_level = "2",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e33}",
        .direction = "ltr",
        .cluster_level = "3",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e34}\u{0e33}",
        .direction = "ltr",
        .cluster_level = "0",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e34}\u{0e33}",
        .direction = "ltr",
        .cluster_level = "1",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e34}\u{0e33}",
        .direction = "ltr",
        .cluster_level = "2",
        .no_positions = true,
    },
    .{
        .font_hash = "4fac3929fc3332834e93673780ec0fe94342d193",
        .text = " \u{0e34}\u{0e33}",
        .direction = "ltr",
        .cluster_level = "3",
        .no_positions = true,
    },
    .{
        .font_hash = "fd07ea46e4d8368ada1776208c07fd596f727852",
        .text = "\u{0d4e}\u{0d4d}\u{200d}",
        .direction = "ltr",
        .cluster_level = "1",
    },
    .{
        .font_hash = "c2d320136762887c43d245ecd2ffc2c0d57cfcb3",
        .text = "\u{0daf}\u{0dcf}\u{0daf}",
        .direction = "ltr",
    },
    .{
        .font_hash = "6f36d056bad6d478fc0bf7397bd52dc3bd197d5f",
        .text = "\u{099b}\u{09cb}\u{09c8}\u{09c2}\u{09cb}\u{098c}",
        .direction = "ltr",
        .cluster_level = "1",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{0650}\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}\u{0646}\u{064e}\u{0627}",
        .direction = "rtl",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}\u{0646}\u{064e}\u{0627}",
        .direction = "rtl",
        .text_before = "\u{0643}\u{0650}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}\u{0646}\u{064e}\u{0627}",
        .direction = "rtl",
        .text_before = "\u{0643}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{0650}\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_after = "\u{0646}\u{064e}\u{0627}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{0650}\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_after = "\u{0646}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_before = "\u{0643}\u{0650}",
        .text_after = "\u{0646}\u{064e}\u{0627}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{062a}\u{064e}\u{0627}\u{0628}\u{064f}",
        .direction = "rtl",
        .text_before = "\u{0643}",
        .text_after = "\u{0646}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{062a}\u{0628}",
        .direction = "rtl",
        .text_before = "\u{0627}",
    },
    .{
        .font_hash = "65984dfce552a785f564422aadf4715fa07795ad",
        .text = "\u{0643}\u{062a}\u{0628}\u{0627}",
        .direction = "rtl",
        .text_after = "\u{0627}",
    },
    .{
        .font_hash = "3105b51976b879032c66aa93a634b3b3672cd344",
        .text = "\u{064e}",
        .direction = "rtl",
        .bot = true,
    },
    .{
        .font_hash = "3105b51976b879032c66aa93a634b3b3672cd344",
        .text = "\u{064e}",
        .direction = "rtl",
        .text_before = "\u{0627}",
        .bot = true,
    },
    .{
        .font_hash = "5dfad7735c6a67085f1b90d4d497e32907db4c78",
        .text = "\u{1e922}\u{1e923}\u{1e924}\u{1e925}\u{1e926}\u{1e927}\u{1e928}\u{1e929}\u{1e92a}\u{1e92b}\u{1e92c}\u{1e92d}\u{1e92e}\u{1e92f}\u{1e930}\u{1e931}\u{1e932}\u{1e933}\u{1e934}\u{1e935}\u{1e936}\u{1e937}\u{1e938}\u{1e939}\u{1e93a}\u{1e93b}\u{1e93c}\u{1e93d}\u{1e93e}\u{1e93f}\u{1e940}\u{1e941}\u{1e942}\u{1e943}",
        .direction = "rtl",
    },
    .{
        .font_hash = "36b3cea27560cf68b1f3a5d5b6f29d29a96393aa",
        .text = "..",
        .direction = "ltr",
    },
    .{
        .font_hash = "36b3cea27560cf68b1f3a5d5b6f29d29a96393aa",
        .text = "..",
        .direction = "ltr",
        .script = "deva",
    },
    .{
        .font_hash = "36b3cea27560cf68b1f3a5d5b6f29d29a96393aa",
        .text = "..",
        .direction = "ltr",
        .script = "latn",
    },
    .{
        .font_hash = "87f85d17d26f1fe9ad28d7365101958edaefb967",
        .text = "\u{0980}\u{0981}",
        .direction = "ltr",
    },
    .{
        .font_hash = "270b89df543a7e48e206a2d830c0e10e5265c630",
        .text = "\u{0d38}\u{0d4d}\u{0d31}\u{0d4d}\u{0d31}\u{0d4d}",
        .direction = "ltr",
    },
    .{
        .font_hash = "8099955657a54e9ee38a6ba1d6f950ce58e3cc25",
        .text = "\u{0e01}\u{0e34}\u{0e01}",
        .direction = "ltr",
    },
    .{
        .font_hash = "a98e908e2ed21b22228ea59ebcc0f05034c86f2e",
        .text = "ABA",
        .direction = "ltr",
    },
    .{
        .font_hash = "bb9473d2403488714043bcfb946c9f78b86ad627",
        .text = "\u{1030}",
        .direction = "ltr",
    },
    .{
        .font_hash = "8454d22037f892e76614e1645d066689a0200e61",
        .text = "\u{05e0}\u{05b8}\u{0591}\u{05da}\u{05b0}",
        .direction = "rtl",
    },
    .{
        .font_hash = "ffa0f5d2d9025486d8469d8b1fdd983e7632499b",
        .text = "X\u{0303}x\u{0303}jjj\u{0303}j\u{0303}jj",
        .direction = "ltr",
    },
    .{
        .font_hash = "cc5f3d2d717fb6bd4dfae1c16d48a2cb8e12233b",
        .text = "X\u{0303}x\u{0303}jjj\u{0303}j\u{0303}jj",
        .direction = "ltr",
    },
    .{
        .font_hash = "fcdcffbdf1c4c97c05308d7600e4c283eb47dbca",
        .text = "X\u{0303}x\u{0303}jjj\u{0303}j\u{0303}jj",
        .direction = "ltr",
    },
    .{
        .font_hash = "56cfd0e18d07f41c38e9598545a6d369127fc6f9",
        .text = "X\u{0303}x\u{0303}jjj\u{0303}j\u{0303}jj",
        .direction = "ltr",
    },
    .{
        .font_hash = "b31e6c52a31edadc16f1bec9efe6019e2d59824a",
        .text = "\u{0644}\u{064e}\u{0644}\u{064f}\u{0647}",
        .direction = "rtl",
    },
    .{
        .font_hash = "8339c821814d9bad7c77169332327ad8b0f33c81",
        .text = "\u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627} \u{0641}\u{0627}",
        .direction = "ltr",
    },
    .{
        .font_hash = "a59fd13f1525a91cbe529c882e93d9d1fbb80463",
        .text = "AB",
        .direction = "ltr",
    },
    .{
        .font_hash = "NotoNastaliqUrdu-Regular",
        .text = "\u{0648}\u{06cc}\u{06a9}\u{06cc}\u{200c}\u{067e}\u{062f}\u{06cc}\u{0627}",
        .direction = "rtl",
    },
    .{
        .font_hash = "NotoNastaliqUrdu-Regular",
        .text = "\u{200c}\u{0628}\u{0648}\u{062f}\u{0646}",
        .direction = "rtl",
    },
    .{
        .font_hash = "MORXTwentyeight",
        .text = "AxEyyDy",
        .direction = "ltr",
    },
    .{
        .font_hash = "e6185e88b04432fbf373594d5971686bb7dd698d",
        .text = "\u{0b95}\u{0bcd} \u{0b9a}\u{0bcd}",
        .direction = "ltr",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = ".5",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = "1",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = "2",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = "9",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = "24",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = "72",
    },
    .{
        .font_hash = "TRAK",
        .text = "ABC",
        .direction = "ltr",
        .size = "144",
    },
};

const retained_harfrust_text_parity_gates = [_]struct {
    font_hash: []const u8,
    text_file: []const u8,
    direction: []const u8,
    show_flags: bool = false,
    unsafe_to_concat: bool = false,
}{
    .{
        .font_hash = "HarfBust",
        .text_file = "tests/data/harfbust-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "b895f8ff06493cc893ec44de380690ca0074edfa",
        .text_file = "tests/data/hebrew-diacritics-31.txt",
        .direction = "rtl",
    },
    .{
        .font_hash = "872d2955d326bd6676a06f66b8238ebbaabc212f",
        .text_file = "tests/data/kbts-arabic-tests.txt",
        .direction = "rtl",
    },
    .{
        .font_hash = "3e46c3b84c1370a06594736c7f8acebf810bbb3b",
        .text_file = "tests/data/arabic-normalization-3e46-tests.txt",
        .direction = "rtl",
    },
    .{
        .font_hash = "b722a7d09e60421f3efbc706ad348ab47b88567b",
        .text_file = "tests/data/devanagari-old-spec-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "8116e5d8fedfbec74e45dc350d2416d810bed8c4",
        .text_file = "tests/data/devanagari-indic-joiners-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "a6c76d1bafde4a0b1026ebcc932d2e5c6fd02442",
        .text_file = "tests/data/myanmar-ligature-id-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "f4ba5a767ef56a40133844507efb98fee5635e71",
        .text_file = "tests/data/myanmar-syllable-machine-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "9d8c53cb64b8747abdd2b70755cce2ee0eb42ef7",
        .text_file = "tests/data/devanagari-special-prishthamatra-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "1a5face3fcbd929d228235c2f72bbd6f8eb37424",
        .text_file = "tests/data/devanagari-vowel-letter-spoofing-extra-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "881642af1667ae30a54e58de8be904566d00508f",
        .text_file = "tests/data/bengali-vowel-letter-spoofing-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "604026ae5aaca83c49cd8416909d71ba3e1c1194",
        .text_file = "tests/data/gurmukhi-vowel-letter-spoofing-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "2c25beb56d9c556622d56b0b5d02b4670c034f89",
        .text_file = "tests/data/odia-vowel-letter-spoofing-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "03e3f463c3a985bc42096620cc415342818454fb",
        .text_file = "tests/data/telugu-vowel-letter-spoofing-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "7d18685e1529e4ceaad5b6095dfab2f9789e5bce",
        .text_file = "tests/data/kannada-vowel-letter-spoofing-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "af85624080af5627fb050f570d148a62f04fda74",
        .text_file = "tests/data/malayalam-vowel-letter-spoofing-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "5f73fff1ffc07b5a99a90c0909609f2b09fef274",
        .text_file = "tests/data/gurmukhi-special-mark-order-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "7bbd3175734d5d291e1c15271ec0cbb97b626ebf",
        .text_file = "tests/data/kbts-mixed-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "1c2fb74c1b2aa173262734c1f616148f1648cfd6",
        .text_file = "tests/data/bengali-ligature-id-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "3998336402905b8be8301ef7f47cf7e050cbb1bd",
        .text_file = "tests/data/khmer-misc-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "ad01ab2ea1cb1a4d3a2783e2675112ef11ae6404",
        .text_file = "tests/data/khmer-misc-broken-coeng-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "086d83239e8f958391ff6cdd8fda9376a4bd3673",
        .text_file = "tests/data/khmer-misc-broken-xgroup-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "f443753e8ffe8e8aae606cfba158e00334b6efb1",
        .text_file = "tests/data/khmer-indic-joiners-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "63e224dcb3d559d590f80c83b832cfca789e5dcc",
        .text_file = "tests/data/gujarati-indic-joiners-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "b6031119874ae9ff1dd65383a335e361c0962220",
        .text_file = "tests/data/khmer-mark-order-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "a02a7f0ad42c2922cb37ad1358c9df4eb81f1bca",
        .text_file = "tests/data/tibetan-contraction-feff-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "2de1ab4907ab688c0cfc236b0bf51151db38bf2e",
        .text_file = "tests/data/tibetan-contraction-2-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "53374c7ca3657be37efde7ed02ae34229a56ae1f",
        .text_file = "tests/data/emoji-tag-sequence-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "AdobeBlank2",
        .text_file = "tests/data/emoji-clusters-adobeblank2.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "ec404b8524cd56efa5d25524cc8541a0b6604b4f",
        .text_file = "tests/data/arabic-phags-pa-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "34da9aab7bee86c4dfc3b85e423435822fdf4b62",
        .text_file = "tests/data/unsafe-to-concat-tests.txt",
        .direction = "rtl",
        .show_flags = true,
        .unsafe_to_concat = true,
    },
    .{
        .font_hash = "SimpArabicTest",
        .text_file = "tests/data/arabic-fallback-simp-tests.txt",
        .direction = "ltr",
    },
    .{
        .font_hash = "TradArabicTest",
        .text_file = "tests/data/arabic-fallback-trad-tests.txt",
        .direction = "ltr",
    },
};

const retained_inline_cangjie_expected_gates = [_]struct {
    font_hash: []const u8,
    text: []const u8,
    direction: []const u8,
    font_slant: ?[]const u8 = null,
    font_bold: ?[]const u8 = null,
    expected_glyph_ids: []const u8,
    expected_clusters: []const u8,
    expected_x_advances: []const u8,
    expected_y_advances: []const u8,
    expected_x_offsets: []const u8,
    expected_y_offsets: []const u8,
}{
    .{
        .font_hash = "NotoSans-VF.abc",
        .text = "abc",
        .direction = "ttb",
        .font_slant = "0.5",
        .expected_glyph_ids = "1,2,3",
        .expected_clusters = "0,1,2",
        .expected_x_advances = "0,0,0",
        .expected_y_advances = "-1362,-1362,-1362",
        .expected_x_offsets = "-280,-307,-240",
        .expected_y_offsets = "-948,-1056,-949",
    },
    .{
        .font_hash = "NotoSans-VF.abc",
        .text = "abc",
        .direction = "ttb",
        .font_bold = "0.1",
        .expected_glyph_ids = "1,2,3",
        .expected_clusters = "0,1,2",
        .expected_x_advances = "0,0,0",
        .expected_y_advances = "-1362,-1362,-1362",
        .expected_x_offsets = "-430,-457,-390",
        .expected_y_offsets = "-1148,-1256,-1149",
    },
    .{
        .font_hash = "2681c1c72d6484ed3410417f521b1b819b4e2392",
        .text = "\u{3008}",
        .direction = "btt",
        .expected_glyph_ids = "4",
        .expected_clusters = "0",
        .expected_x_advances = "0",
        .expected_y_advances = "-2048",
        .expected_x_offsets = "-1024",
        .expected_y_offsets = "-1720",
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const fontations_coverage_step = b.step(
        "fontations-coverage",
        "Verify Fontations table and high-level capability evidence",
    );
    const fontations_coverage_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/verify_fontations_coverage.py",
    });
    fontations_coverage_step.dependOn(&fontations_coverage_cmd.step);
    const unicode_scripts_path = b.option(
        []const u8,
        "unicode-scripts",
        "Unicode 17 Scripts.txt path for the script coverage audit",
    );
    const unicode_script_extensions_path = b.option(
        []const u8,
        "unicode-script-extensions",
        "Unicode 17 ScriptExtensions.txt path for the script extension audit",
    );
    const unicode_property_value_aliases_path = b.option(
        []const u8,
        "unicode-property-value-aliases",
        "Unicode 17 PropertyValueAliases.txt path for script aliases",
    );
    const unicode_script_coverage_step = b.step(
        "unicode-script-coverage",
        "Verify the Unicode 17 shaping-script coverage frontier",
    );
    if (unicode_scripts_path) |path| {
        const unicode_script_coverage_cmd = b.addSystemCommand(&.{
            "python3",
            "tools/unicode/script/verify_coverage.py",
            path,
        });
        const unicode_script_test_source = unicode_script_coverage_cmd.addOutputFileArg(
            "script_coverage_test.zig",
        );
        const unicode_script_probe = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = unicode_script_test_source,
                .target = target,
                .optimize = .ReleaseSafe,
            }),
        });
        unicode_script_probe.root_module.addImport(
            "script",
            b.createModule(.{
                .root_source_file = b.path("src/unicode/script/root.zig"),
                .target = target,
                .optimize = .ReleaseSafe,
            }),
        );
        unicode_script_coverage_step.dependOn(
            &b.addRunArtifact(unicode_script_probe).step,
        );
    } else {
        const missing_unicode_scripts = b.addFail(
            "unicode-script-coverage requires -Dunicode-scripts=/path/to/Scripts.txt",
        );
        unicode_script_coverage_step.dependOn(&missing_unicode_scripts.step);
    }
    const enable_harfbuzz = b.option(bool, "enable-harfbuzz", "Build shape-bench with the HarfBuzz reference engine") orelse false;
    const harfbuzz_prefix = b.option([]const u8, "harfbuzz-prefix", "Prefix containing HarfBuzz include/ and lib/");
    const harfbuzz_include_dir = b.option([]const u8, "harfbuzz-include-dir", "Directory containing hb.h and hb-ot.h");
    const harfbuzz_lib_dir = b.option([]const u8, "harfbuzz-lib-dir", "Directory containing libharfbuzz");
    const parity_work_root = b.option([]const u8, "parity-work-root", "Root containing local harfbuzz/, harfrust/, and KaTeX/ checkouts for shaping parity gates") orelse if (b.graph.environ_map.get("HOME")) |home|
        b.fmt("{s}/Work", .{home})
    else
        null;
    const imx_dep = b.dependency("imx", .{
        .target = target,
        .optimize = optimize,
    });
    const vort_dep = b.dependency("vort", .{
        .target = target,
        .optimize = optimize,
    });

    const mod = b.addModule("cangjie", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "imx", .module = imx_dep.module("imx") },
            .{ .name = "vort", .module = vort_dep.module("vort") },
        },
    });

    const unicode_script_extensions_step = b.step(
        "unicode-script-extensions",
        "Verify Unicode 17 Script_Extensions coverage",
    );
    if (unicode_scripts_path != null and
        unicode_script_extensions_path != null and
        unicode_property_value_aliases_path != null)
    {
        const verify_extensions = b.addSystemCommand(&.{
            "python3",
            "tools/unicode/script_extensions/verify_coverage.py",
            unicode_scripts_path.?,
            unicode_script_extensions_path.?,
            unicode_property_value_aliases_path.?,
        });
        const generated_test = verify_extensions.addOutputFileArg(
            "script_extensions_test.zig",
        );
        const extension_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = generated_test,
                .target = target,
                .optimize = .ReleaseSafe,
            }),
        });
        extension_test.root_module.addImport(
            "cangjie",
            mod,
        );
        unicode_script_extensions_step.dependOn(
            &b.addRunArtifact(extension_test).step,
        );
    } else {
        const missing_extensions = b.addFail(
            "unicode-script-extensions requires -Dunicode-scripts, " ++
                "-Dunicode-script-extensions, and -Dunicode-property-value-aliases",
        );
        unicode_script_extensions_step.dependOn(&missing_extensions.step);
    }

    const tests = b.addTest(.{
        .root_module = mod,
    });
    const system_font_raster_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/system_font_raster_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });

    const test_step = b.step("test", "Run cangjie font tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);
    test_step.dependOn(&b.addRunArtifact(system_font_raster_tests).step);

    const font_descriptor_bench_mod = b.createModule(.{
        .root_source_file = b.path("tools/font_descriptor_bench.zig"),
        .target = target,
        .optimize = .ReleaseFast,
        .imports = &.{.{ .name = "cangjie", .module = mod }},
    });
    const font_descriptor_bench = b.addExecutable(.{ .name = "cangjie-font-descriptor-bench", .root_module = font_descriptor_bench_mod });
    const run_font_descriptor_bench = b.addRunArtifact(font_descriptor_bench);
    if (b.args) |args| run_font_descriptor_bench.addArgs(args) else run_font_descriptor_bench.addArgs(&.{
        "--faces=4096",                              "--iterations=20000",
        "--max-exact-ns-per-query=100000",           "--max-portable-ns-per-query=100000",
        "--max-codec-ns-per-roundtrip=10000",        "--expect-checksum=12971938209271991909",
        "--json=zig-out/font_descriptor_bench.json",
    });
    const font_descriptor_bench_step = b.step("font-descriptor-bench", "Benchmark stable font descriptor codec and deterministic resolver");
    font_descriptor_bench_step.dependOn(&run_font_descriptor_bench.step);
    const font_descriptor_bench_tests = b.addTest(.{ .root_module = font_descriptor_bench_mod });
    const font_descriptor_bench_test_step = b.step("test-font-descriptor-bench", "Run scaled stable font descriptor benchmark tests");
    font_descriptor_bench_test_step.dependOn(&b.addRunArtifact(font_descriptor_bench_tests).step);
    test_step.dependOn(font_descriptor_bench_test_step);

    const system_font_raster_test_step = b.step("system-font-raster-test", "Run macOS system font raster regression tests");
    system_font_raster_test_step.dependOn(&b.addRunArtifact(system_font_raster_tests).step);

    const font_fuzz_smoke_exe = b.addExecutable(.{
        .name = "cangjie-font-fuzz-smoke",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/font_fuzz_smoke.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cangjie", .module = mod }},
        }),
    });
    const font_fuzz_smoke_step = b.step(
        "font-fuzz-smoke",
        "Run deterministic malformed-font parser, shaper, and renderer mutations",
    );
    const font_fuzz_smoke_cmd = b.addRunArtifact(font_fuzz_smoke_exe);
    font_fuzz_smoke_step.dependOn(&font_fuzz_smoke_cmd.step);
    if (b.args) |args| {
        font_fuzz_smoke_cmd.addArgs(args);
    }

    const font_fuzz_seeds = b.addWriteFiles();
    _ = font_fuzz_seeds.addCopyFile(
        b.path("src/tests/data/fontations_cmap12_font1.ttf"),
        "font_fuzz/seeds/fontations_cmap12_font1.ttf",
    );
    _ = font_fuzz_seeds.addCopyFile(
        b.path("src/tests/data/fontations_names_only.ttf"),
        "font_fuzz/seeds/fontations_names_only.ttf",
    );
    _ = font_fuzz_seeds.addCopyFile(
        b.path("src/tests/data/fontations_simple_glyf.ttf"),
        "font_fuzz/seeds/fontations_simple_glyf.ttf",
    );
    _ = font_fuzz_seeds.addCopyFile(
        b.path("src/tests/data/fontations_cmap14_font1.ttf"),
        "font_fuzz/seeds/fontations_cmap14_font1.ttf",
    );
    _ = font_fuzz_seeds.addCopyFile(
        b.path("src/tests/data/fontations_vazirmatn_var.ttf"),
        "font_fuzz/seeds/fontations_vazirmatn_var.ttf",
    );
    _ = font_fuzz_seeds.addCopyFile(
        b.path("tests/data/fontations/vorg.ttf"),
        "font_fuzz/seeds/vorg.ttf",
    );
    _ = font_fuzz_seeds.addCopyFile(
        b.path("tools/font_fuzz/driver.zig"),
        "font_fuzz/driver.zig",
    );
    const font_fuzz_cangjie = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .imports = &.{
            .{ .name = "imx", .module = imx_dep.module("imx") },
            .{ .name = "vort", .module = vort_dep.module("vort") },
        },
    });
    const font_fuzz_tests = b.addTest(.{
        .name = "cangjie-font-fuzz",
        .root_module = b.createModule(.{
            .root_source_file = font_fuzz_seeds.addCopyFile(
                b.path("tools/font_fuzz_test.zig"),
                "font_fuzz_test.zig",
            ),
            .target = target,
            // Memory safety is the contract under test even when the rest of
            // the build requests ReleaseFast.
            .optimize = .ReleaseSafe,
            .imports = &.{.{ .name = "cangjie", .module = font_fuzz_cangjie }},
        }),
    });
    const font_fuzz_step = b.step(
        "font-fuzz",
        "Fuzz malformed font parsing, shaping, and rendering with Zig's built-in fuzzer",
    );
    font_fuzz_step.dependOn(&b.addRunArtifact(font_fuzz_tests).step);

    const render_text_exe = b.addExecutable(.{
        .name = "cangjie-render-text",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/render_text.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });

    const render_text_step = b.step("render-text", "Render text from a TTF/OTF font into a grayscale PGM image");
    const render_text_cmd = b.addRunArtifact(render_text_exe);
    render_text_step.dependOn(&render_text_cmd.step);
    if (b.args) |args| {
        render_text_cmd.addArgs(args);
    }

    const line_break_bench_exe = b.addExecutable(.{
        .name = "cangjie-line-break-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/line_break_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{
                    .name = "line_break",
                    .module = b.createModule(.{
                        .root_source_file = b.path("src/unicode/line_break/iterator.zig"),
                        .target = target,
                        .optimize = optimize,
                    }),
                },
            },
        }),
    });

    const line_break_bench_step = b.step("line-break-bench", "Benchmark streaming Unicode line breaking");
    const line_break_bench_cmd = b.addRunArtifact(line_break_bench_exe);
    line_break_bench_step.dependOn(&line_break_bench_cmd.step);
    if (b.args) |args| {
        line_break_bench_cmd.addArgs(args);
    }

    const reflow_bench_exe = b.addExecutable(.{
        .name = "cangjie-reflow-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/reflow_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });

    const reflow_bench_step = b.step("reflow-bench", "Compare repeated shaping with retained paragraph reflow");
    const reflow_bench_cmd = b.addRunArtifact(reflow_bench_exe);
    reflow_bench_step.dependOn(&reflow_bench_cmd.step);
    if (b.args) |args| {
        reflow_bench_cmd.addArgs(args);
    }

    const paragraph_bench_exe = b.addExecutable(.{
        .name = "cangjie-paragraph-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/paragraph_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
            },
        }),
    });
    const paragraph_bench_step = b.step(
        "paragraph-bench",
        "Benchmark end-to-end paragraph construction for Parley comparison",
    );
    const paragraph_bench_cmd = b.addRunArtifact(paragraph_bench_exe);
    paragraph_bench_step.dependOn(&paragraph_bench_cmd.step);
    if (b.args) |args| paragraph_bench_cmd.addArgs(args);

    const parley_matrix_step = b.step(
        "parley-matrix",
        "Run the cross-script Cangjie/Parley paragraph matrix",
    );
    const parley_matrix_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/run_parley_matrix.py",
        "--cangjie",
    });
    parley_matrix_cmd.addArtifactArg(paragraph_bench_exe);
    parley_matrix_cmd.addArgs(&.{
        "--parley-manifest",
        "tools/parley_layout_oracle/Cargo.toml",
        "--parley-root",
        b.fmt("{s}/parley", .{parity_work_root orelse ""}),
        "--roboto",
        b.fmt("{s}/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf", .{parity_work_root orelse ""}),
        "--arabic-font",
        "/usr/share/fonts/truetype/noto/NotoKufiArabic-Regular.ttf",
        "--japanese-font",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "--fallback-font",
        b.fmt("{s}/harfrust/harfrust/benches/fonts/NotoSansDevanagari-Regular.ttf", .{parity_work_root orelse ""}),
    });
    if (b.args) |args| parley_matrix_cmd.addArgs(args);
    parley_matrix_step.dependOn(&parley_matrix_cmd.step);

    const freetype_c = b.addTranslateC(.{
        .root_source_file = b.path("tools/glyph_bench/freetype.h"),
        .target = target,
        .optimize = optimize,
    });
    freetype_c.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });

    const hinting_freetype_c = b.addTranslateC(.{
        .root_source_file = b.path("tests/hinting_freetype.h"),
        .target = target,
        .optimize = optimize,
    });
    hinting_freetype_c.linkSystemLibrary(
        "freetype2",
        .{ .use_pkg_config = .force },
    );
    const hinting_freetype_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/hinting_freetype_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
                .{
                    .name = "freetype",
                    .module = hinting_freetype_c.createModule(),
                },
            },
        }),
    });
    hinting_freetype_tests.root_module.linkSystemLibrary(
        "freetype2",
        .{ .use_pkg_config = .force },
    );
    const hinting_freetype_test_step = b.step(
        "hinting-freetype-test",
        "Compare hinted TrueType outlines with FreeType v35 and v40",
    );
    hinting_freetype_test_step.dependOn(
        &b.addRunArtifact(hinting_freetype_tests).step,
    );

    const shape_bench_options = b.addOptions();
    shape_bench_options.addOption(bool, "enable_harfbuzz", enable_harfbuzz);
    const shape_bench_mod = b.createModule(.{
        .root_source_file = b.path("tools/shape_bench.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "cangjie", .module = mod },
            .{ .name = "shape_bench_options", .module = shape_bench_options.createModule() },
        },
    });
    if (enable_harfbuzz) {
        const harfbuzz_c = b.addTranslateC(.{
            .root_source_file = b.path("tools/shape_bench/harfbuzz.h"),
            .target = target,
            .optimize = optimize,
        });
        if (harfbuzz_prefix) |prefix| {
            const include_dir = b.fmt("{s}/include/harfbuzz", .{prefix});
            const lib_dir = b.fmt("{s}/lib", .{prefix});
            harfbuzz_c.addSystemIncludePath(.{ .cwd_relative = include_dir });
            shape_bench_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
            shape_bench_mod.addRPath(.{ .cwd_relative = lib_dir });
        }
        if (harfbuzz_include_dir) |include_dir| {
            harfbuzz_c.addSystemIncludePath(.{ .cwd_relative = include_dir });
        }
        if (harfbuzz_lib_dir) |lib_dir| {
            shape_bench_mod.addLibraryPath(.{ .cwd_relative = lib_dir });
            shape_bench_mod.addRPath(.{ .cwd_relative = lib_dir });
        }
        if (harfbuzz_prefix == null and harfbuzz_include_dir == null) {
            harfbuzz_c.linkSystemLibrary("harfbuzz", .{ .use_pkg_config = .force });
        }
        harfbuzz_c.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });
        shape_bench_mod.linkSystemLibrary("harfbuzz", .{
            .use_pkg_config = if (harfbuzz_prefix == null and harfbuzz_lib_dir == null) .force else .no,
        });
        shape_bench_mod.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });
        shape_bench_mod.addImport("harfbuzz", harfbuzz_c.createModule());
    }
    if (target.result.os.tag == .macos) {
        shape_bench_mod.linkFramework("CoreFoundation", .{});
        shape_bench_mod.linkFramework("CoreGraphics", .{});
        shape_bench_mod.linkFramework("CoreText", .{});
    }

    const shape_bench_exe = b.addExecutable(.{
        .name = "cangjie-shape-bench",
        .root_module = shape_bench_mod,
    });

    const shape_bench_step = b.step("shape-bench", "Benchmark Cangjie text shaping");
    const shape_bench_cmd = b.addRunArtifact(shape_bench_exe);
    shape_bench_step.dependOn(&shape_bench_cmd.step);
    if (b.args) |args| {
        shape_bench_cmd.addArgs(args);
    }

    const shaping_parity_smoke_step = b.step("shaping-parity-smoke", "Run retained HarfBuzz shaping parity smoke gates");
    const shaping_use_parity_smoke_step = b.step("shaping-use-parity-smoke", "Run retained HarfBuzz USE fixture parity smoke gates");
    const shaping_aat_parity_smoke_step = b.step("shaping-aat-parity-smoke", "Run retained AAT shaping parity gates");
    const shaping_corpus_parity_smoke_step = b.step("shaping-corpus-parity-smoke", "Run retained HarfBuzz Latin, Arabic, and variable-font corpus parity gates");
    const shaping_performance_matrix_step = b.step(
        "shaping-performance-matrix",
        "Benchmark Cangjie against HarfBuzz/HarfRust; --fail-on-slower uses a 1.01x minimum",
    );
    if (!enable_harfbuzz) {
        shaping_parity_smoke_step.dependOn(&b.addFail("shaping-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_use_parity_smoke_step.dependOn(&b.addFail("shaping-use-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_aat_parity_smoke_step.dependOn(&b.addFail("shaping-aat-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_corpus_parity_smoke_step.dependOn(&b.addFail("shaping-corpus-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_performance_matrix_step.dependOn(&b.addFail("shaping-performance-matrix requires -Denable-harfbuzz=true").step);
    } else if (parity_work_root == null) {
        shaping_parity_smoke_step.dependOn(&b.addFail("shaping-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_use_parity_smoke_step.dependOn(&b.addFail("shaping-use-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_aat_parity_smoke_step.dependOn(&b.addFail("shaping-aat-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_corpus_parity_smoke_step.dependOn(&b.addFail("shaping-corpus-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_performance_matrix_step.dependOn(&b.addFail("shaping-performance-matrix requires HOME or -Dparity-work-root=/path/to/Work").step);
    } else {
        const work_root = parity_work_root.?;
        const harfrust_benches = b.fmt("{s}/harfrust/harfrust/benches", .{work_root});
        const shaping_performance_matrix_cmd = b.addSystemCommand(&.{
            "python3",
            "tools/run_shaping_performance_matrix.py",
            "--cangjie",
        });
        shaping_performance_matrix_cmd.addArtifactArg(shape_bench_exe);
        shaping_performance_matrix_cmd.addArgs(&.{
            "--harfbuzz",
        });
        shaping_performance_matrix_cmd.addArtifactArg(shape_bench_exe);
        shaping_performance_matrix_cmd.addArgs(&.{
            "--harfrust-manifest",
            "tools/harfrust_shape_oracle/Cargo.toml",
            "--corpus-root",
            harfrust_benches,
        });
        if (b.args) |args| shaping_performance_matrix_cmd.addArgs(args);
        shaping_performance_matrix_step.dependOn(
            &shaping_performance_matrix_cmd.step,
        );
        const harfbuzz_in_house_fonts = b.fmt("{s}/harfbuzz/test/shape/data/in-house/fonts", .{work_root});
        const harfbuzz_text_rendering_fonts = b.fmt("{s}/harfbuzz/test/shape/data/text-rendering-tests/fonts", .{work_root});
        const harfbuzz_aots_fonts = b.fmt("{s}/harfbuzz/test/shape/data/aots/fonts", .{work_root});
        const honokamin_font = b.fmt("{s}/KaTeX/test/screenshotter/fonts/mincho/font_1_honokamin.ttf", .{work_root});

        const dev_parity_cmd = b.addRunArtifact(shape_bench_exe);
        dev_parity_cmd.addArgs(&.{
            "--engine",    "compare-harfbuzz",
            "--font",      b.fmt("{s}/fonts/NotoSansDevanagari-Regular.ttf", .{harfrust_benches}),
            "--text-file", b.fmt("{s}/texts/hi-words.txt", .{harfrust_benches}),
            "--direction", "ltr",
        });
        shaping_parity_smoke_step.dependOn(&dev_parity_cmd.step);

        const duployan_parity_cmd = b.addRunArtifact(shape_bench_exe);
        duployan_parity_cmd.addArgs(&.{
            "--engine",    "compare-harfbuzz",
            "--font",      b.fmt("{s}/harfbuzz/perf/fonts/NotoSansDuployan-Regular.otf", .{work_root}),
            "--text-file", b.fmt("{s}/texts/duployan.txt", .{harfrust_benches}),
            "--direction", "ltr",
        });
        shaping_parity_smoke_step.dependOn(&duployan_parity_cmd.step);

        for (retained_corpus_parity_gates) |gate| {
            const corpus_parity_cmd = b.addRunArtifact(shape_bench_exe);
            corpus_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfrust_benches, gate.font_file }),
                "--text-file", b.fmt("{s}/{s}", .{ harfrust_benches, gate.text_file }),
                "--direction", gate.direction,
            });
            if (gate.language) |language| {
                corpus_parity_cmd.addArgs(&.{ "--language", language });
            }
            shaping_corpus_parity_smoke_step.dependOn(&corpus_parity_cmd.step);

            const corpus_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            corpus_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfrust_benches, gate.font_file }),
                "--text-file", b.fmt("{s}/{s}", .{ harfrust_benches, gate.text_file }),
                "--direction", gate.direction,
            });
            if (gate.language) |language| {
                corpus_harfrust_parity_cmd.addArgs(&.{ "--language", language });
            }
            shaping_corpus_parity_smoke_step.dependOn(&corpus_harfrust_parity_cmd.step);
        }
        for (retained_aots_parity_gates) |gate| {
            // AOTS fonts are generated specifically for one OpenType feature.
            // Retain the exact lookup-cursor and modulo-delta boundaries that
            // broad natural-language corpora are unlikely to synthesize.
            const font_path = b.fmt("{s}/{s}", .{ harfbuzz_aots_fonts, gate.font_file });
            const harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfbuzz_parity_cmd.addArgs(&.{
                "--engine",         "compare-harfbuzz",
                "--font",           font_path,
                "--text",           gate.text,
                "--direction",      "ltr",
                "--enable-feature", "test",
            });
            if (gate.no_positions) harfbuzz_parity_cmd.addArg("--no-positions");
            shaping_corpus_parity_smoke_step.dependOn(&harfbuzz_parity_cmd.step);

            const harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfrust_parity_cmd.addArgs(&.{
                "--engine",         "compare-harfrust",
                "--font",           font_path,
                "--text",           gate.text,
                "--direction",      "ltr",
                "--enable-feature", "test",
            });
            if (gate.no_positions) harfrust_parity_cmd.addArg("--no-positions");
            shaping_corpus_parity_smoke_step.dependOn(&harfrust_parity_cmd.step);
        }
        for (retained_aots_feature_range_gates) |gate| {
            const font_path = b.fmt("{s}/{s}", .{ harfbuzz_aots_fonts, gate.font_file });
            inline for ([_][]const u8{ "compare-harfbuzz", "compare-harfrust" }) |engine| {
                const parity_cmd = b.addRunArtifact(shape_bench_exe);
                parity_cmd.addArgs(&.{
                    "--engine",       engine,
                    "--font",         font_path,
                    "--text",         gate.text,
                    "--direction",    "ltr",
                    "--no-positions",
                });
                for (gate.ranges) |range| {
                    parity_cmd.addArgs(&.{ "--feature-range", range });
                }
                shaping_corpus_parity_smoke_step.dependOn(&parity_cmd.step);
            }
        }
        for (retained_inline_harfbuzz_parity_gates) |gate| {
            if (gate.known_current_harfbuzz_difference) continue;
            const inline_parity_cmd = b.addRunArtifact(shape_bench_exe);
            inline_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.{s}", .{ harfbuzz_in_house_fonts, gate.font_hash, gate.font_ext }),
                "--text",      gate.text,
                "--direction", gate.direction,
            });
            if (gate.not_found_variation_selector_glyph) |glyph_id| {
                inline_parity_cmd.addArgs(&.{ "--not-found-variation-selector-glyph", glyph_id });
            }
            if (gate.face_index) |face_index| {
                inline_parity_cmd.addArgs(&.{ "--face-index", face_index });
            }
            if (gate.script) |script| {
                inline_parity_cmd.addArgs(&.{ "--script", script });
            }
            if (gate.language) |language| {
                inline_parity_cmd.addArgs(&.{ "--language", language });
            }
            if (gate.enable_feature) |feature| {
                inline_parity_cmd.addArgs(&.{ "--enable-feature", feature });
            }
            if (gate.enable_feature_2) |feature| {
                inline_parity_cmd.addArgs(&.{ "--enable-feature", feature });
            }
            if (gate.disable_feature) |feature| {
                inline_parity_cmd.addArgs(&.{ "--disable-feature", feature });
            }
            if (gate.variation) |variation| {
                inline_parity_cmd.addArgs(&.{ "--variation", variation });
            }
            if (gate.show_extents) {
                inline_parity_cmd.addArg("--show-extents");
            }
            if (gate.text_before) |text_before| {
                inline_parity_cmd.addArgs(&.{ "--text-before", text_before });
            }
            if (gate.text_after) |text_after| {
                inline_parity_cmd.addArgs(&.{ "--text-after", text_after });
            }
            if (gate.bot) {
                inline_parity_cmd.addArg("--bot");
            }
            shaping_corpus_parity_smoke_step.dependOn(&inline_parity_cmd.step);
        }
        for (retained_harfbuzz_text_parity_gates) |gate| {
            const text_parity_cmd = b.addRunArtifact(shape_bench_exe);
            text_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&text_parity_cmd.step);
        }
        for (retained_myanmar_text_parity_gates) |gate| {
            const font_path = b.fmt(
                "{s}/{s}.ttf",
                .{ harfbuzz_in_house_fonts, gate.font_hash },
            );
            inline for ([_][]const u8{
                "compare-harfbuzz",
                "compare-harfrust",
            }) |engine| {
                const myanmar_parity_cmd = b.addRunArtifact(shape_bench_exe);
                myanmar_parity_cmd.addArgs(&.{
                    "--engine",    engine,
                    "--font",      font_path,
                    "--text-file", gate.text_file,
                    "--direction", "ltr",
                });
                shaping_corpus_parity_smoke_step.dependOn(
                    &myanmar_parity_cmd.step,
                );
            }
        }
        for (retained_text_rendering_parity_gates) |gate| {
            const harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfbuzz_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
            });
            if (gate.size) |size| harfbuzz_parity_cmd.addArgs(&.{ "--size", size });
            if (gate.remove_default_ignorables) harfbuzz_parity_cmd.addArg("--remove-default-ignorables");
            shaping_corpus_parity_smoke_step.dependOn(&harfbuzz_parity_cmd.step);

            const harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
            });
            if (gate.size) |size| harfrust_parity_cmd.addArgs(&.{ "--size", size });
            if (gate.remove_default_ignorables) harfrust_parity_cmd.addArg("--remove-default-ignorables");
            shaping_corpus_parity_smoke_step.dependOn(&harfrust_parity_cmd.step);
        }
        for (retained_text_rendering_expected_gates) |gate| {
            const expected_cmd = b.addRunArtifact(shape_bench_exe);
            expected_cmd.addArgs(&.{
                "--font",            b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file",       gate.text_file,
                "--direction",       gate.direction,
                "--size",            gate.size,
                "--iterations",      "1",
                "--warmup",          "0",
                "--samples",         "1",
                "--expect-checksum", gate.expected_checksum,
            });
            if (gate.remove_default_ignorables) expected_cmd.addArg("--remove-default-ignorables");
            shaping_corpus_parity_smoke_step.dependOn(&expected_cmd.step);
        }
        for (retained_inline_text_rendering_parity_gates) |gate| {
            const harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfbuzz_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text",      gate.text,
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&harfbuzz_parity_cmd.step);

            const harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text",      gate.text,
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&harfrust_parity_cmd.step);
        }
        for (retained_variable_text_rendering_parity_gates) |gate| {
            // Keep every upstream design-space sample as a separate process.
            // A single corpus run cannot vary coordinates per line, and
            // collapsing the samples would leave interpolation boundaries
            // untested even when both endpoints happen to agree.
            for (gate.variations) |variation| {
                const harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
                harfbuzz_parity_cmd.addArgs(&.{
                    "--engine",    "compare-harfbuzz",
                    "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                    "--text",      gate.text,
                    "--direction", gate.direction,
                    "--size",      gate.size,
                    "--variation", variation,
                });
                if (gate.remove_default_ignorables) harfbuzz_parity_cmd.addArg("--remove-default-ignorables");
                if (gate.harfbuzz_extents) harfbuzz_parity_cmd.addArg("--show-extents");
                shaping_corpus_parity_smoke_step.dependOn(&harfbuzz_parity_cmd.step);

                const harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
                harfrust_parity_cmd.addArgs(&.{
                    "--engine",    "compare-harfrust",
                    "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                    "--text",      gate.text,
                    "--direction", gate.direction,
                    "--size",      gate.size,
                    "--variation", variation,
                });
                if (gate.remove_default_ignorables) harfrust_parity_cmd.addArg("--remove-default-ignorables");
                shaping_corpus_parity_smoke_step.dependOn(&harfrust_parity_cmd.step);
            }
        }
        for (retained_extents_text_rendering_parity_gates) |gate| {
            const harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfbuzz_parity_cmd.addArgs(&.{
                "--engine",       "compare-harfbuzz",
                "--font",         b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file",    gate.text_file,
                "--direction",    gate.direction,
                "--size",         gate.size,
                "--show-extents",
            });
            if (gate.remove_default_ignorables) harfbuzz_parity_cmd.addArg("--remove-default-ignorables");
            shaping_corpus_parity_smoke_step.dependOn(&harfbuzz_parity_cmd.step);

            const harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
                "--size",      gate.size,
            });
            if (gate.remove_default_ignorables) harfrust_parity_cmd.addArg("--remove-default-ignorables");
            shaping_corpus_parity_smoke_step.dependOn(&harfrust_parity_cmd.step);
        }
        for (retained_text_rendering_rejection_gates) |gate| {
            const rejection_cmd = b.addRunArtifact(shape_bench_exe);
            rejection_cmd.addArgs(&.{
                "--font",       b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text",       gate.text,
                "--direction",  gate.direction,
                "--iterations", "1",
                "--warmup",     "0",
                "--samples",    "1",
            });
            rejection_cmd.expectExitCode(1);
            rejection_cmd.expectStdErrMatch("error: ShapingLimitExceeded");
            shaping_corpus_parity_smoke_step.dependOn(&rejection_cmd.step);
        }
        for (retained_inline_harfrust_parity_gates) |gate| {
            const inline_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            inline_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}.{s}", .{ harfbuzz_in_house_fonts, gate.font_hash, gate.font_ext }),
                "--text",      gate.text,
                "--direction", gate.direction,
            });
            if (gate.variation) |variation| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--variation", variation });
            }
            if (gate.script) |script| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--script", script });
            }
            if (gate.disable_feature) |feature| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--disable-feature", feature });
            }
            if (gate.size) |size| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--size", size });
            }
            if (gate.cluster_level) |cluster_level| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--cluster-level", cluster_level });
            }
            if (gate.no_positions) {
                inline_harfrust_parity_cmd.addArg("--no-positions");
            }
            if (gate.text_before) |text_before| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--text-before", text_before });
            }
            if (gate.text_after) |text_after| {
                inline_harfrust_parity_cmd.addArgs(&.{ "--text-after", text_after });
            }
            if (gate.bot) {
                inline_harfrust_parity_cmd.addArg("--bot");
            }
            shaping_corpus_parity_smoke_step.dependOn(&inline_harfrust_parity_cmd.step);
        }
        for (retained_harfrust_custom_parity_gates) |gate| {
            const font_path = b.fmt(
                "{s}/harfrust/harfrust/tests/fonts/rb_custom/{s}",
                .{ work_root, gate.font_file },
            );
            const custom_harfrust_parity_cmd =
                b.addRunArtifact(shape_bench_exe);
            custom_harfrust_parity_cmd.addArgs(&.{
                "--engine",     "compare-harfrust",
                "--font",       font_path,
                "--text",       gate.text,
                "--direction",  "ltr",
                "--iterations", "1",
                "--warmup",     "0",
                "--samples",    "1",
            });
            shaping_corpus_parity_smoke_step.dependOn(
                &custom_harfrust_parity_cmd.step,
            );
        }
        for (retained_inline_cangjie_expected_gates) |gate| {
            const expected_cmd = b.addRunArtifact(shape_bench_exe);
            expected_cmd.addArgs(&.{
                "--font",                 b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text",                 gate.text,
                "--direction",            gate.direction,
                "--glyph-summary",        "--iterations",
                "1",                      "--warmup",
                "0",                      "--samples",
                "1",                      "--expect-glyph-ids",
                gate.expected_glyph_ids,  "--expect-clusters",
                gate.expected_clusters,   "--expect-x-advances",
                gate.expected_x_advances, "--expect-y-advances",
                gate.expected_y_advances, "--expect-x-offsets",
                gate.expected_x_offsets,  "--expect-y-offsets",
                gate.expected_y_offsets,
            });
            if (gate.font_slant) |font_slant| {
                expected_cmd.addArgs(&.{ "--font-slant", font_slant });
            }
            if (gate.font_bold) |font_bold| {
                expected_cmd.addArgs(&.{ "--font-bold", font_bold });
            }
            shaping_corpus_parity_smoke_step.dependOn(&expected_cmd.step);
        }
        for (retained_vertical_text_rendering_parity_gates) |gate| {
            const font_path = b.fmt(
                "{s}/{s}",
                .{ harfbuzz_in_house_fonts, gate.font_file },
            );
            const engines = [_][]const u8{
                "compare-harfbuzz",
                "compare-harfrust",
            };
            const engine_count: usize = if (gate.harfrust) 2 else 1;
            for (engines[0..engine_count]) |engine| {
                const vertical_parity_cmd =
                    b.addRunArtifact(shape_bench_exe);
                vertical_parity_cmd.addArgs(&.{
                    "--engine",    engine,
                    "--font",      font_path,
                    "--text",      gate.text,
                    "--direction", "ttb",
                });
                if (gate.size) |size| {
                    vertical_parity_cmd.addArgs(&.{ "--size", size });
                }
                if (gate.variation) |variation| {
                    vertical_parity_cmd.addArgs(&.{
                        "--variation",
                        variation,
                    });
                }
                shaping_corpus_parity_smoke_step.dependOn(
                    &vertical_parity_cmd.step,
                );
            }
        }
        for (retained_harfrust_text_parity_gates) |gate| {
            const text_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            text_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
            });
            if (gate.unsafe_to_concat) {
                text_harfrust_parity_cmd.addArg("--unsafe-to-concat");
            }
            if (gate.show_flags) {
                text_harfrust_parity_cmd.addArg("--show-flags");
            }
            shaping_corpus_parity_smoke_step.dependOn(&text_harfrust_parity_cmd.step);
        }
        shaping_parity_smoke_step.dependOn(shaping_corpus_parity_smoke_step);

        for (retained_use_fixture_hashes) |hash| {
            const use_parity_cmd = b.addRunArtifact(shape_bench_exe);
            use_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, hash }),
                "--text-file", b.fmt("tests/data/use/{s}.txt", .{hash}),
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&use_parity_cmd.step);

            const use_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            use_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, hash }),
                "--text-file", b.fmt("tests/data/use/{s}.txt", .{hash}),
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&use_harfrust_parity_cmd.step);
        }
        for (retained_compact_use_gates) |gate| {
            const compact_use_parity_cmd = b.addRunArtifact(shape_bench_exe);
            compact_use_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&compact_use_parity_cmd.step);

            const compact_use_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            compact_use_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}.ttf", .{ harfbuzz_in_house_fonts, gate.font_hash }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_use_parity_smoke_step.dependOn(&compact_use_harfrust_parity_cmd.step);
        }
        shaping_parity_smoke_step.dependOn(shaping_use_parity_smoke_step);

        for (retained_morx_rearrangement_gates) |gate| {
            const morx_harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfbuzz_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfbuzz_parity_cmd.step);

            const morx_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfrust_parity_cmd.step);
        }
        for (retained_morx_contextual_gates) |gate| {
            const morx_harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfbuzz_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfbuzz_parity_cmd.step);

            const morx_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", gate.direction,
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfrust_parity_cmd.step);
        }
        for (retained_morx_insertion_gates) |gate| {
            const morx_harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfbuzz_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfbuzz_parity_cmd.step);

            const morx_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfrust_parity_cmd.step);
        }
        for (retained_morx_complete_gates) |gate| {
            const morx_harfbuzz_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfbuzz_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfbuzz",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfbuzz_parity_cmd.step);

            const morx_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            morx_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text-file", gate.text_file,
                "--direction", "ltr",
            });
            shaping_aat_parity_smoke_step.dependOn(&morx_harfrust_parity_cmd.step);
        }
        for (retained_morx_rejection_gates) |gate| {
            const morx_rejection_cmd = b.addRunArtifact(shape_bench_exe);
            morx_rejection_cmd.addArgs(&.{
                "--font",       b.fmt("{s}/{s}", .{ harfbuzz_text_rendering_fonts, gate.font_file }),
                "--text",       gate.text,
                "--direction",  "ltr",
                "--iterations", "1",
                "--warmup",     "0",
                "--samples",    "1",
            });
            morx_rejection_cmd.expectExitCode(1);
            morx_rejection_cmd.expectStdErrMatch("error: BadSfnt");
            shaping_aat_parity_smoke_step.dependOn(&morx_rejection_cmd.step);
        }

        const kerx_format_0_cmd = b.addRunArtifact(shape_bench_exe);
        kerx_format_0_cmd.addArgs(&.{
            "--builtin",       "kerx",
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "785,785",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-15",           "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_0_cmd.step);

        const kerx_variation_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "kerx-variation",
            "kerx-variation.ttf",
        );
        const kerx_variation_default_harfbuzz = b.addRunArtifact(shape_bench_exe);
        kerx_variation_default_harfbuzz.addArgs(&.{ "--engine", "compare-harfbuzz", "--font" });
        kerx_variation_default_harfbuzz.addFileArg(kerx_variation_font);
        kerx_variation_default_harfbuzz.addArgs(&.{
            "--text",       "AA",
            "--direction",  "ltr",
            "--iterations", "1",
            "--warmup",     "0",
            "--samples",    "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_variation_default_harfbuzz.step);

        // HarfBuzz currently returns only the first vector member, so
        // non-default tuple interpolation is guarded by the Apple-specified
        // expected result rather than a knowingly incomplete reference.
        const kerx_variation_half_expected = b.addRunArtifact(shape_bench_exe);
        kerx_variation_half_expected.addArg("--font");
        kerx_variation_half_expected.addFileArg(kerx_variation_font);
        kerx_variation_half_expected.addArgs(&.{
            "--text",          "AA",
            "--size",          "1000",
            "--variation",     "0.5",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "780,780",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-20",           "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_variation_half_expected.step);

        const kerx_format_1_cmd = b.addRunArtifact(shape_bench_exe);
        kerx_format_1_cmd.addArgs(&.{
            "--builtin",       "kerx-format-1",
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "770,800",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "-30,0",           "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_1_cmd.step);

        const kerx_format_2_cmd = b.addRunArtifact(shape_bench_exe);
        kerx_format_2_cmd.addArgs(&.{
            "--builtin",       "kerx-format-2",
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "785,785",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-15",           "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_2_cmd.step);

        const kerx_format_4_cmd = b.addRunArtifact(shape_bench_exe);
        kerx_format_4_cmd.addArgs(&.{
            "--builtin",       "kerx-format-4",
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "800,800",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-830",          "--expect-y-offsets",
            "0,25",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_4_cmd.step);

        const kerx_format_4_outline_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "kerx-format-4-outline",
            "kerx-format-4-outline.ttf",
        );
        const kerx_format_4_outline_harfbuzz = b.addRunArtifact(shape_bench_exe);
        kerx_format_4_outline_harfbuzz.addArgs(&.{
            "--engine",                  "compare-harfbuzz",
            "--harfbuzz-freetype-funcs", "--font",
        });
        kerx_format_4_outline_harfbuzz.addFileArg(kerx_format_4_outline_font);
        kerx_format_4_outline_harfbuzz.addArgs(&.{
            "--text",       "AA",
            "--direction",  "ltr",
            "--iterations", "1",
            "--warmup",     "0",
            "--samples",    "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_4_outline_harfbuzz.step);

        const kerx_format_4_outline_expected = b.addRunArtifact(shape_bench_exe);
        kerx_format_4_outline_expected.addArg("--font");
        kerx_format_4_outline_expected.addFileArg(kerx_format_4_outline_font);
        kerx_format_4_outline_expected.addArgs(&.{
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "800,800",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-450",          "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_4_outline_expected.step);

        const kerx_format_4_ankr_cmd = b.addRunArtifact(shape_bench_exe);
        kerx_format_4_ankr_cmd.addArgs(&.{
            "--builtin",       "kerx-format-4-ankr",
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "800,800",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-800",          "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_4_ankr_cmd.step);

        const kerx_format_6_cmd = b.addRunArtifact(shape_bench_exe);
        kerx_format_6_cmd.addArgs(&.{
            "--builtin",       "kerx-format-6",
            "--text",          "AA",
            "--size",          "1000",
            "--glyph-summary", "--iterations",
            "1",               "--warmup",
            "0",               "--samples",
            "1",               "--expect-glyph-ids",
            "1,1",             "--expect-clusters",
            "0,1",             "--expect-x-advances",
            "785,785",         "--expect-y-advances",
            "0,0",             "--expect-x-offsets",
            "0,-15",           "--expect-y-offsets",
            "0,0",
        });
        shaping_aat_parity_smoke_step.dependOn(&kerx_format_6_cmd.step);

        addKerxCrossStreamParityGates(b, shape_bench_exe, shaping_aat_parity_smoke_step);

        const mort_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "mort",
            "mort-noncontextual.ttf",
        );
        const mort_harfbuzz = b.addRunArtifact(shape_bench_exe);
        mort_harfbuzz.addArgs(&.{ "--engine", "compare-harfbuzz", "--font" });
        mort_harfbuzz.addFileArg(mort_font);
        mort_harfbuzz.addArgs(&.{
            "--text",       "A",
            "--direction",  "ltr",
            "--iterations", "1",
            "--warmup",     "0",
            "--samples",    "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&mort_harfbuzz.step);

        const mort_rearrangement_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "mort-rearrangement",
            "mort-rearrangement.ttf",
        );
        const mort_rearrangement_harfbuzz = b.addRunArtifact(shape_bench_exe);
        mort_rearrangement_harfbuzz.addArgs(&.{ "--engine", "compare-harfbuzz", "--font" });
        mort_rearrangement_harfbuzz.addFileArg(mort_rearrangement_font);
        mort_rearrangement_harfbuzz.addArgs(&.{
            "--text",       "AB",
            "--direction",  "ltr",
            "--iterations", "1",
            "--warmup",     "0",
            "--samples",    "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&mort_rearrangement_harfbuzz.step);

        const mort_contextual_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "mort-contextual",
            "mort-contextual.ttf",
        );
        const mort_contextual_harfbuzz = b.addRunArtifact(shape_bench_exe);
        mort_contextual_harfbuzz.addArgs(&.{ "--engine", "compare-harfbuzz", "--font" });
        mort_contextual_harfbuzz.addFileArg(mort_contextual_font);
        mort_contextual_harfbuzz.addArgs(&.{
            "--text",       "AB",
            "--direction",  "ltr",
            "--iterations", "1",
            "--warmup",     "0",
            "--samples",    "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&mort_contextual_harfbuzz.step);

        const mort_ligature_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "mort-ligature",
            "mort-ligature.ttf",
        );
        const mort_ligature_harfbuzz = b.addRunArtifact(shape_bench_exe);
        mort_ligature_harfbuzz.addArgs(&.{ "--engine", "compare-harfbuzz", "--font" });
        mort_ligature_harfbuzz.addFileArg(mort_ligature_font);
        mort_ligature_harfbuzz.addArgs(&.{
            "--text",             "AB",
            "--direction",        "ltr",
            "--expect-glyph-ids", "3",
            "--expect-clusters",  "0",
            "--iterations",       "1",
            "--warmup",           "0",
            "--samples",          "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&mort_ligature_harfbuzz.step);

        const mort_insertion_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            "mort-insertion",
            "mort-insertion.ttf",
        );
        const mort_insertion_harfbuzz = b.addRunArtifact(shape_bench_exe);
        mort_insertion_harfbuzz.addArgs(&.{ "--engine", "compare-harfbuzz", "--font" });
        mort_insertion_harfbuzz.addFileArg(mort_insertion_font);
        mort_insertion_harfbuzz.addArgs(&.{
            "--text",             "A",
            "--direction",        "ltr",
            "--expect-glyph-ids", "1,2",
            "--expect-clusters",  "0,0",
            "--iterations",       "1",
            "--warmup",           "0",
            "--samples",          "1",
        });
        shaping_aat_parity_smoke_step.dependOn(&mort_insertion_harfbuzz.step);

        // Hide Honoka's redundant GSUB directory record for both engines. The
        // unchanged mort payload and complete corpus then prove standalone
        // legacy substitution instead of letting OpenType `vert` hide it.
        const mort_only_harfbuzz = b.addRunArtifact(shape_bench_exe);
        mort_only_harfbuzz.addArgs(&.{
            "--engine",                                      "compare-harfbuzz",
            "--font",                                        honokamin_font,
            "--hide-gsub-table",                             "--text-file",
            "tests/data/vertical/honokamin-mort-mapped.txt", "--direction",
            "ttb",
        });
        shaping_aat_parity_smoke_step.dependOn(&mort_only_harfbuzz.step);

        const global_vert_harfbuzz_cmd = b.addRunArtifact(shape_bench_exe);
        global_vert_harfbuzz_cmd.addArgs(&.{
            "--engine",    "compare-harfbuzz",
            "--font",      honokamin_font,
            "--text-file", "tests/data/vertical/honokamin-mort-mapped.txt",
            "--direction", "ttb",
        });
        shaping_aat_parity_smoke_step.dependOn(&global_vert_harfbuzz_cmd.step);

        const global_vert_harfrust_cmd = b.addRunArtifact(shape_bench_exe);
        global_vert_harfrust_cmd.addArgs(&.{
            "--engine",    "compare-harfrust",
            "--font",      honokamin_font,
            "--text-file", "tests/data/vertical/honokamin-mort-mapped.txt",
            "--direction", "ttb",
        });
        shaping_aat_parity_smoke_step.dependOn(&global_vert_harfrust_cmd.step);
        shaping_parity_smoke_step.dependOn(shaping_aat_parity_smoke_step);
    }

    const glyph_bench_exe = b.addExecutable(.{
        .name = "cangjie-glyph-bench",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/glyph_bench.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "cangjie", .module = mod },
                .{ .name = "freetype", .module = freetype_c.createModule() },
                .{ .name = "imx", .module = imx_dep.module("imx") },
            },
        }),
    });

    const glyph_bench_step = b.step("glyph-bench", "Benchmark Cangjie glyph outline/raster hot paths");
    const glyph_bench_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_bench_step.dependOn(&glyph_bench_cmd.step);
    if (b.args) |args| {
        glyph_bench_cmd.addArgs(args);
    }

    const freetype_matrix_step = b.step(
        "freetype-matrix",
        "Benchmark Cangjie against FreeType across raster formats, sizes, and lifecycles",
    );
    const freetype_matrix_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/run_freetype_matrix.py",
        "--glyph-bench",
    });
    freetype_matrix_cmd.addArtifactArg(glyph_bench_exe);
    freetype_matrix_cmd.addArgs(&.{
        "--roboto",
        b.fmt("{s}/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf", .{parity_work_root orelse ""}),
        "--cff",
        "/usr/share/fonts/opentype/stix/STIXGeneral-Regular.otf",
        "--cff2",
        b.fmt("{s}/harfbuzz/test/subset/data/fonts/Cantarell-VF-ABC.otf", .{parity_work_root orelse ""}),
        "--arabic",
        "/usr/share/fonts/truetype/noto/NotoKufiArabic-Regular.ttf",
        "--cjk",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
        "--cbdt",
        b.fmt("{s}/harfbuzz/test/fuzzing/fonts/NotoColorEmoji.subset.ttf", .{parity_work_root orelse ""}),
        "--sbix",
        b.fmt("{s}/harfbuzz/test/fuzzing/fonts/sbix.ttf", .{parity_work_root orelse ""}),
        "--colr-v0",
        b.fmt("{s}/harfbuzz/test/subset/data/expected/colr_glyphs/BungeeColor-Regular.default.41.ttf", .{parity_work_root orelse ""}),
    });
    if (b.args) |args| freetype_matrix_cmd.addArgs(args);
    freetype_matrix_step.dependOn(&freetype_matrix_cmd.step);

    const hinted_outline_matrix_step = b.step(
        "hinted-outline-matrix",
        "Benchmark matched hinted outlines against FreeType",
    );
    const hinted_outline_matrix_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/run_hinted_outline_matrix.py",
        "--glyph-bench",
    });
    hinted_outline_matrix_cmd.addArtifactArg(glyph_bench_exe);
    if (b.args) |args| hinted_outline_matrix_cmd.addArgs(args);
    hinted_outline_matrix_step.dependOn(&hinted_outline_matrix_cmd.step);

    const glyph_name_fixtures_exe = b.addExecutable(.{
        .name = "cangjie-glyph-name-fixtures",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/glyph_name_fixtures/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "test_font", .module = b.createModule(.{
                    .root_source_file = b.path("src/test_font.zig"),
                    .target = target,
                    .optimize = optimize,
                }) },
            },
        }),
    });
    const glyph_name_fixtures_step = b.step(
        "glyph-name-fixtures",
        "Write generated Fontations metadata and outline fixtures",
    );
    const glyph_name_fixtures_cmd = b.addRunArtifact(glyph_name_fixtures_exe);
    const generated_fontations_fixtures =
        glyph_name_fixtures_cmd.addOutputDirectoryArg("fixtures");
    glyph_name_fixtures_step.dependOn(&glyph_name_fixtures_cmd.step);

    const colrv1_pixel_exe = b.addExecutable(.{
        .name = "cangjie-colrv1-pixel",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/colrv1_pixel_cangjie.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "cangjie", .module = mod }},
        }),
    });
    const colrv1_pixel_matrix_step = b.step(
        "colrv1-pixel-matrix",
        "Run the Cangjie/Skrifa COLRv1 pixel differential",
    );
    const colrv1_pixel_matrix_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/run_colrv1_pixel_matrix.py",
        "--cangjie",
    });
    colrv1_pixel_matrix_cmd.addArtifactArg(colrv1_pixel_exe);
    colrv1_pixel_matrix_cmd.addArgs(&.{
        "--skrifa-manifest",
        "tools/colrv1_pixel_oracle/Cargo.toml",
        "--font",
    });
    colrv1_pixel_matrix_cmd.addFileArg(
        b.path("tests/data/fontations/colrv1-pixel-corpus.ttf"),
    );
    if (b.args) |args| colrv1_pixel_matrix_cmd.addArgs(args);
    colrv1_pixel_matrix_step.dependOn(&colrv1_pixel_matrix_cmd.step);

    const fontations_matrix_step = b.step(
        "fontations-matrix",
        "Run the reproducible Cangjie/Skrifa capability matrix",
    );
    const fontations_matrix_cmd = b.addSystemCommand(&.{
        "python3",
        "tools/run_fontations_matrix.py",
        "--cangjie",
    });
    fontations_matrix_cmd.addArtifactArg(glyph_bench_exe);
    fontations_matrix_cmd.addArgs(&.{
        "--skrifa-manifest",
        "tools/fontations_bitmap_oracle/Cargo.toml",
        "--fixture-dir",
    });
    fontations_matrix_cmd.addDirectoryArg(generated_fontations_fixtures);
    fontations_matrix_cmd.addArgs(&.{
        "--roboto",
        b.fmt(
            "{s}/harfrust/harfrust/benches/fonts/Roboto-Regular.ttf",
            .{parity_work_root orelse ""},
        ),
        "--cff2",
        b.fmt(
            "{s}/harfbuzz/test/subset/data/fonts/Cantarell-VF-ABC.otf",
            .{parity_work_root orelse ""},
        ),
        "--varc",
    });
    fontations_matrix_cmd.addFileArg(
        b.path("tests/data/fontations/varc-ac01-conditional.ttf"),
    );
    if (b.args) |args| fontations_matrix_cmd.addArgs(args);
    fontations_matrix_step.dependOn(&fontations_matrix_cmd.step);

    const bench_smoke_step = b.step("bench-smoke", "Run quick TSV smoke checks for benchmark tools");
    const paragraph_bench_smoke_cmd = b.addRunArtifact(paragraph_bench_exe);
    paragraph_bench_smoke_cmd.addArg("builtin:minimal");
    paragraph_bench_smoke_cmd.addFileArg(b.path("tests/data/spaces-horizontal.txt"));
    paragraph_bench_smoke_cmd.addArgs(&.{ "1", "1" });
    bench_smoke_step.dependOn(&paragraph_bench_smoke_cmd.step);
    const shape_bench_smoke_cmd = b.addRunArtifact(shape_bench_exe);
    shape_bench_smoke_cmd.addArgs(&.{
        "--engine",     "cangjie",
        "--format",     "tsv",
        "--builtin",    "script-feature",
        "--text",       "A",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&shape_bench_smoke_cmd.step);

    const paragraph_spacing_smoke_cmd = b.addRunArtifact(paragraph_bench_exe);
    paragraph_spacing_smoke_cmd.addArg("builtin:minimal");
    paragraph_spacing_smoke_cmd.addFileArg(b.path("tests/data/spaces-horizontal.txt"));
    paragraph_spacing_smoke_cmd.addArgs(&.{
        "1", "1", "200", "layout", "ltr", "spacing",
    });
    bench_smoke_step.dependOn(&paragraph_spacing_smoke_cmd.step);
    const paragraph_alternating_smoke_cmd = b.addRunArtifact(paragraph_bench_exe);
    paragraph_alternating_smoke_cmd.addArg("builtin:minimal");
    paragraph_alternating_smoke_cmd.addFileArg(b.path("tests/data/spaces-horizontal.txt"));
    paragraph_alternating_smoke_cmd.addArgs(&.{
        "1", "1", "200", "layout", "ltr", "alternating",
    });
    bench_smoke_step.dependOn(&paragraph_alternating_smoke_cmd.step);

    const glyph_outline_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_outline_smoke_cmd.addArgs(&.{
        "--mode",       "outline",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
        "--variation",  "0.5",
    });
    bench_smoke_step.dependOn(&glyph_outline_smoke_cmd.step);

    const glyph_bounds_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_bounds_smoke_cmd.addArgs(&.{
        "--mode",       "bounds",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_bounds_smoke_cmd.step);

    const glyph_global_metrics_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_global_metrics_smoke_cmd.addArgs(&.{
        "--mode",       "global-metrics",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_global_metrics_smoke_cmd.step);

    const glyph_name_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_name_smoke_cmd.addArgs(&.{
        "--mode",       "glyph-name",
        "--format",     "tsv",
        "--builtin",    "minimal",
        "--glyph-id",   "1",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_name_smoke_cmd.step);

    const glyph_attributes_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_attributes_smoke_cmd.addArgs(&.{
        "--mode",       "attributes",
        "--format",     "tsv",
        "--builtin",    "minimal",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_attributes_smoke_cmd.step);

    const glyph_variations_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_variations_smoke_cmd.addArgs(&.{
        "--mode",       "variations",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_variations_smoke_cmd.step);

    const glyph_palettes_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_palettes_smoke_cmd.addArgs(&.{
        "--mode",       "palettes",
        "--format",     "tsv",
        "--builtin",    "minimal",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_palettes_smoke_cmd.step);

    const glyph_strikes_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_strikes_smoke_cmd.addArgs(&.{
        "--mode",       "strikes",
        "--format",     "tsv",
        "--builtin",    "cbdt-bgra",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_strikes_smoke_cmd.step);

    const glyph_color_source_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_color_source_smoke_cmd.addArgs(&.{
        "--mode",       "color-glyph",
        "--format",     "tsv",
        "--builtin",    "minimal",
        "--glyph-id",   "1",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_color_source_smoke_cmd.step);

    const glyph_color_layers_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_color_layers_smoke_cmd.addArgs(&.{
        "--engine",     "compare-freetype",
        "--mode",       "color-layers",
        "--format",     "tsv",
        "--builtin",    "color-v0",
        "--glyph-id",   "1",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_color_layers_smoke_cmd.step);

    const glyph_freetype_outline_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_freetype_outline_smoke_cmd.addArgs(&.{
        "--engine",     "freetype",
        "--mode",       "outline",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_freetype_outline_smoke_cmd.step);

    const glyph_freetype_raster_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_freetype_raster_smoke_cmd.addArgs(&.{
        "--engine",     "freetype",
        "--mode",       "raster",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_freetype_raster_smoke_cmd.step);

    const glyph_bitmap_render_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_bitmap_render_smoke_cmd.addArgs(&.{
        "--engine",     "compare-freetype",
        "--mode",       "bitmap-render",
        "--format",     "tsv",
        "--builtin",    "cbdt-bgra",
        "--glyph-id",   "1",
        "--font-size",  "16",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_bitmap_render_smoke_cmd.step);

    inline for (.{
        .{ .fixture = "cbdt-png", .glyph_id = "1" },
        .{ .fixture = "ebdt-mask", .glyph_id = "1" },
        .{ .fixture = "ebdt-compound", .glyph_id = "2" },
    }) |bitmap_case| {
        const glyph_bitmap_format_smoke_cmd =
            b.addRunArtifact(glyph_bench_exe);
        glyph_bitmap_format_smoke_cmd.addArgs(&.{
            "--engine",     "compare-freetype",
            "--mode",       "bitmap-render",
            "--format",     "tsv",
            "--builtin",    bitmap_case.fixture,
            "--glyph-id",   bitmap_case.glyph_id,
            "--font-size",  "16",
            "--iterations", "1",
            "--warmup",     "0",
            "--samples",    "1",
        });
        bench_smoke_step.dependOn(&glyph_bitmap_format_smoke_cmd.step);
    }

    const glyph_freetype_raster_reuse_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_freetype_raster_reuse_smoke_cmd.addArgs(&.{
        "--engine",     "freetype",
        "--mode",       "raster-reuse",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_freetype_raster_reuse_smoke_cmd.step);

    const glyph_compare_freetype_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_compare_freetype_smoke_cmd.addArgs(&.{
        "--engine",     "compare-freetype",
        "--mode",       "outline",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_compare_freetype_smoke_cmd.step);

    const glyph_compare_freetype_raster_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_compare_freetype_raster_smoke_cmd.addArgs(&.{
        "--engine",     "compare-freetype",
        "--mode",       "raster",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    bench_smoke_step.dependOn(&glyph_compare_freetype_raster_smoke_cmd.step);

    const glyph_raster_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_smoke_cmd.addArgs(&.{
        "--mode",             "raster",
        "--format",           "tsv",
        "--builtin",          "gvar-compound",
        "--iterations",       "1",
        "--warmup",           "0",
        "--samples",          "1",
        "--samples-per-axis", "2",
        "--variation",        "0.5",
    });
    bench_smoke_step.dependOn(&glyph_raster_smoke_cmd.step);

    const glyph_raster_reuse_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_reuse_smoke_cmd.addArgs(&.{
        "--mode",       "raster-reuse",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
        "--variation",  "0.5",
    });
    bench_smoke_step.dependOn(&glyph_raster_reuse_smoke_cmd.step);

    const glyph_raster_prepared_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_prepared_smoke_cmd.addArgs(&.{
        "--mode",       "raster-prepared",
        "--format",     "tsv",
        "--builtin",    "gvar-compound",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
        "--variation",  "0.5",
    });
    bench_smoke_step.dependOn(&glyph_raster_prepared_smoke_cmd.step);

    const glyph_raster_dirty_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_raster_dirty_smoke_cmd.addArgs(&.{
        "--mode",        "raster-prepared",
        "--dirty-rect",  "--format",
        "tsv",           "--builtin",
        "gvar-compound", "--iterations",
        "1",             "--warmup",
        "0",             "--samples",
        "1",
    });
    bench_smoke_step.dependOn(&glyph_raster_dirty_smoke_cmd.step);

    const glyph_freetype_dirty_smoke_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_freetype_dirty_smoke_cmd.addArgs(&.{
        "--engine",      "freetype",
        "--mode",        "raster-reuse",
        "--dirty-rect",  "--format",
        "tsv",           "--builtin",
        "gvar-compound", "--iterations",
        "1",             "--warmup",
        "0",             "--samples",
        "1",
    });
    bench_smoke_step.dependOn(&glyph_freetype_dirty_smoke_cmd.step);
}

fn addKerxCrossStreamParityGates(
    b: *std.Build,
    shape_bench_exe: *std.Build.Step.Compile,
    parity_step: *std.Build.Step,
) void {
    const specs = [_]struct {
        format: []const u8,
        horizontal_builtin: []const u8,
        vertical_builtin: []const u8,
    }{
        .{ .format = "0", .horizontal_builtin = "kerx-cross-format-0", .vertical_builtin = "kerx-cross-vertical-format-0" },
        .{ .format = "1", .horizontal_builtin = "kerx-cross-format-1", .vertical_builtin = "kerx-cross-vertical-format-1" },
        .{ .format = "2", .horizontal_builtin = "kerx-cross-format-2", .vertical_builtin = "kerx-cross-vertical-format-2" },
        .{ .format = "6", .horizontal_builtin = "kerx-cross-format-6", .vertical_builtin = "kerx-cross-vertical-format-6" },
    };
    for (specs) |spec| {
        const horizontal_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            spec.horizontal_builtin,
            b.fmt("kerx-cross-format-{s}.ttf", .{spec.format}),
        );
        addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, horizontal_font, "compare-harfbuzz", false, false);
        addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, horizontal_font, "compare-harfrust", false, false);
        if (std.mem.eql(u8, spec.format, "1")) {
            addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, horizontal_font, "compare-harfbuzz", false, true);
            addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, horizontal_font, "compare-harfrust", false, true);
        }

        const vertical_font = exportedBuiltinFont(
            b,
            shape_bench_exe,
            spec.vertical_builtin,
            b.fmt("kerx-cross-vertical-format-{s}.ttf", .{spec.format}),
        );
        addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, vertical_font, "compare-harfbuzz", true, false);
        addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, vertical_font, "compare-harfrust", true, false);
    }

    const reset_font = exportedBuiltinFont(
        b,
        shape_bench_exe,
        "kerx-cross-format-1-reset",
        "kerx-cross-format-1-reset.ttf",
    );
    addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, reset_font, "compare-harfbuzz", false, false);
    addCrossStreamReferenceGate(b, shape_bench_exe, parity_step, reset_font, "compare-harfrust", false, false);
}

fn exportedBuiltinFont(
    b: *std.Build,
    shape_bench_exe: *std.Build.Step.Compile,
    builtin: []const u8,
    basename: []const u8,
) std.Build.LazyPath {
    const command = b.addRunArtifact(shape_bench_exe);
    command.addArgs(&.{ "--builtin", builtin, "--export-font" });
    return command.addOutputFileArg(basename);
}

fn addCrossStreamReferenceGate(
    b: *std.Build,
    shape_bench_exe: *std.Build.Step.Compile,
    parity_step: *std.Build.Step,
    font: std.Build.LazyPath,
    engine: []const u8,
    vertical: bool,
    disable_kerning: bool,
) void {
    const command = b.addRunArtifact(shape_bench_exe);
    command.addArgs(&.{ "--engine", engine, "--font" });
    command.addFileArg(font);
    command.addArgs(&.{
        "--text",       "AAA",
        "--direction",  if (vertical) "ttb" else "ltr",
        "--iterations", "1",
        "--warmup",     "0",
        "--samples",    "1",
    });
    if (vertical) command.addArgs(&.{ "--enable-feature", "vkrn" });
    if (disable_kerning) command.addArgs(&.{ "--disable-feature", "kern" });
    parity_step.dependOn(&command.step);
}
