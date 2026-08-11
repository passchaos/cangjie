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
        .font_hash = "3c96e7a303c58475a8c750bf4289bbe73784f37d",
        .text_file = "tests/data/use-indic3-tests.txt",
    },
    .{
        .font_hash = "3cc01fede4debd4b7794ccb1b16cdb9987ea7571",
        .text_file = "tests/data/tai-tham-use-syllable-tests.txt",
    },
};

const retained_corpus_parity_gates = [_]struct {
    font_file: []const u8,
    text_file: []const u8,
    direction: []const u8,
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
};

const retained_inline_harfbuzz_parity_gates = [_]struct {
    font_hash: []const u8,
    text: []const u8,
    direction: []const u8,
    script: ?[]const u8 = null,
    language: ?[]const u8 = null,
    enable_feature: ?[]const u8 = null,
    enable_feature_2: ?[]const u8 = null,
    variation: ?[]const u8 = null,
    not_found_variation_selector_glyph: ?[]const u8 = null,
    font_ext: []const u8 = "ttf",
}{
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
        .font_hash = "8116e5d8fedfbec74e45dc350d2416d810bed8c4",
        .text = "\u{091f}\u{094d}\u{200c}\u{092f}\u{093f}",
        .direction = "ltr",
    },
    .{
        .font_hash = "8116e5d8fedfbec74e45dc350d2416d810bed8c4",
        .text = "\u{091f}\u{094d}\u{200d}\u{091f}\u{094d}\u{200c}\u{091f}\u{094d}\u{200d}\u{092f}\u{093f}",
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
        .variation = "0,0.7,0",
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
        .variation = "0,0.7,0",
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
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const enable_harfbuzz = b.option(bool, "enable-harfbuzz", "Build shape-bench with the HarfBuzz reference engine") orelse false;
    const harfbuzz_prefix = b.option([]const u8, "harfbuzz-prefix", "Prefix containing HarfBuzz include/ and lib/");
    const harfbuzz_include_dir = b.option([]const u8, "harfbuzz-include-dir", "Directory containing hb.h and hb-ot.h");
    const harfbuzz_lib_dir = b.option([]const u8, "harfbuzz-lib-dir", "Directory containing libharfbuzz");
    const parity_work_root = b.option([]const u8, "parity-work-root", "Root containing local harfbuzz/ and harfrust/ reference checkouts for shaping parity gates") orelse if (b.graph.environ_map.get("HOME")) |home|
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

    const system_font_raster_test_step = b.step("system-font-raster-test", "Run macOS system font raster regression tests");
    system_font_raster_test_step.dependOn(&b.addRunArtifact(system_font_raster_tests).step);

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
                        .root_source_file = b.path("src/text/line_break.zig"),
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

    const freetype_c = b.addTranslateC(.{
        .root_source_file = b.path("tools/glyph_bench/freetype.h"),
        .target = target,
        .optimize = optimize,
    });
    freetype_c.linkSystemLibrary("freetype2", .{ .use_pkg_config = .force });

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
        shape_bench_mod.linkSystemLibrary("harfbuzz", .{
            .use_pkg_config = if (harfbuzz_prefix == null and harfbuzz_lib_dir == null) .force else .no,
        });
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
    const shaping_corpus_parity_smoke_step = b.step("shaping-corpus-parity-smoke", "Run retained HarfBuzz Latin, Arabic, and variable-font corpus parity gates");
    if (!enable_harfbuzz) {
        shaping_parity_smoke_step.dependOn(&b.addFail("shaping-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_use_parity_smoke_step.dependOn(&b.addFail("shaping-use-parity-smoke requires -Denable-harfbuzz=true").step);
        shaping_corpus_parity_smoke_step.dependOn(&b.addFail("shaping-corpus-parity-smoke requires -Denable-harfbuzz=true").step);
    } else if (parity_work_root == null) {
        shaping_parity_smoke_step.dependOn(&b.addFail("shaping-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_use_parity_smoke_step.dependOn(&b.addFail("shaping-use-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
        shaping_corpus_parity_smoke_step.dependOn(&b.addFail("shaping-corpus-parity-smoke requires HOME or -Dparity-work-root=/path/to/Work").step);
    } else {
        const work_root = parity_work_root.?;
        const harfrust_benches = b.fmt("{s}/harfrust/harfrust/benches", .{work_root});
        const harfbuzz_in_house_fonts = b.fmt("{s}/harfbuzz/test/shape/data/in-house/fonts", .{work_root});

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
            shaping_corpus_parity_smoke_step.dependOn(&corpus_parity_cmd.step);

            const corpus_harfrust_parity_cmd = b.addRunArtifact(shape_bench_exe);
            corpus_harfrust_parity_cmd.addArgs(&.{
                "--engine",    "compare-harfrust",
                "--font",      b.fmt("{s}/{s}", .{ harfrust_benches, gate.font_file }),
                "--text-file", b.fmt("{s}/{s}", .{ harfrust_benches, gate.text_file }),
                "--direction", gate.direction,
            });
            shaping_corpus_parity_smoke_step.dependOn(&corpus_harfrust_parity_cmd.step);
        }
        for (retained_inline_harfbuzz_parity_gates) |gate| {
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
            if (gate.variation) |variation| {
                inline_parity_cmd.addArgs(&.{ "--variation", variation });
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
            },
        }),
    });

    const glyph_bench_step = b.step("glyph-bench", "Benchmark Cangjie glyph outline/raster hot paths");
    const glyph_bench_cmd = b.addRunArtifact(glyph_bench_exe);
    glyph_bench_step.dependOn(&glyph_bench_cmd.step);
    if (b.args) |args| {
        glyph_bench_cmd.addArgs(args);
    }

    const bench_smoke_step = b.step("bench-smoke", "Run quick TSV smoke checks for benchmark tools");
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
}
