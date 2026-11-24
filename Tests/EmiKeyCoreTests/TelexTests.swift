import XCTest
@testable import EmiKeyCore

final class TelexTests: XCTestCase {
    let t = TelexEngine()

    func check(_ pairs: [(String, String?)], style: ToneStyle = .new, file: StaticString = #filePath, line: UInt = #line) {
        for (raw, want) in pairs {
            XCTAssertEqual(t.transform(raw, style: style), want, "telex \(raw)", file: file, line: line)
        }
    }

    func testMarksAndTones() {
        check([
            ("aa", nil), ("aan", "ân"), ("aw", nil /* ă needs a final */), ("ee", "ê"), ("oo", "ô"), ("ow", "ơ"), ("uw", "ư"),
            ("ddi", "đi"), ("did", "đi"), ("dda", "đa"), ("tw", "tư"), ("w", "ư"),
            ("as", "á"), ("af", "à"), ("ar", "ả"), ("ax", "ã"), ("aj", "ạ"),
            ("vieetj", "việt"), ("vietje", "việt"), ("vieejt", "việt"), ("tieengs", "tiếng"),
            ("nguowif", "người"), ("dduowngf", "đường"), ("tooi", "tôi"), ("quaj", "quạ"), ("giuwax", "giữa"),
            ("xinf", "xìn"), ("chaof", "chào"), ("banj", "bạn"), ("khoong", "không"), ("cuar", "của"),
            ("ddeemf", "đềm"), ("nhaf", "nhà"), ("trwowngf", "trường"), ("truwowngf", "trường"),
            ("hoawcj", "hoặc"), ("muwa", "mưa"), ("muaf", "mùa"), ("ruwowuj", "rượu"), ("cuwus", "cứu"),
            ("yeeu", "yêu"), ("yeeus", "yếu"), ("nghieeng", "nghiêng"), ("ddaau", "đâu"), ("caay", "cây"),
            ("nawng", "năng"), ("nawngs", "nắng"), ("luaan", "luân"), ("xuaan", "xuân"), ("khuyeen", "khuyên"),
            ("ddeens", "đến"), ("ddoongf", "đồng"), ("ddeemj", "đệm"),
            ("hocj", "học"), ("sachs", "sách"), ("anhr", "ảnh"), ("mootj", "một"), ("hai", nil), ("baa", nil),
            ("gif", "gì"), ("gias", "giá"), ("quoocs", "quốc"), ("cos", "có"), ("khongz", nil), ("khoongsz", "không"),
            ("ddaauf", "đầu"), ("dduwngs", "đứng"), ("ngoaif", "ngoài"), ("khuyar", "khuỷa"), ("tiens", nil /* iê needs ê */),
        ])
    }

    func testToneStyles() {
        check([("hoaf", "hoà"), ("thuys", "thuý"), ("khoer", "khoẻ"), ("hoaf", "hoà"), ("hoanf", "hoàn"), ("quys", "quý")], style: .new)
        check([("hoaf", "hòa"), ("thuys", "thúy"), ("khoer", "khỏe"), ("hoanf", "hoàn"), ("quys", "quý"), ("thuyr", "thủy")], style: .old)
    }

    func testCapitals() {
        check([("Vieetj", "Việt"), ("VIEETJ", "VIỆT"), ("DDi", "Đi"), ("DDUOWNGF", "ĐƯỜNG"), ("Tooi", "Tôi"),
               ("NGUOWIF", "NGƯỜI"), ("Nguowif", "Người"), ("HOAF", "HOÀ")])
    }

    func testUndo() {
        check([("ass", "as"), ("aaa", "aa"), ("ddd", "dd"), ("ooo", "oo"), ("eee", "ee"), ("aff", "af"),
               ("uww", "uw"), ("oww", "ow")])
    }

    func testEnglishStaysNil() {
        check([("class", nil), ("git", nil), ("went", nil), ("wow", nil), ("aws", nil), ("the", nil),
               ("ma", nil), ("hello", nil), ("change", nil), ("my", nil), ("street", nil), ("swift", nil),
               ("javascript", nil), ("ww", "ww"), ("www", "www"), ("abc", nil), ("mp3", nil), ("cat", nil)])
    }

    func testToneConstraints() {
        check([("hocf", nil), ("matr", nil), ("satx", nil), ("bacs", "bác"), ("bacj", "bạc"), ("tetf", nil)])
    }

    func testSyllableValidator() {
        for w in ["việt", "người", "cho", "con", "tôi", "giữa", "quạ", "nghiêng", "khuya", "oai", "the", "anh"] {
            XCTAssertTrue(VietSyllable.isValid(w), w)
        }
        for w in ["bus", "take", "class", "test", "git", "ci", "ghá", "ngi", "yt", "iêt", "kan", "ge"] {
            XCTAssertFalse(VietSyllable.isValid(w), w)
        }
        XCTAssertTrue(VietSyllable.isValid("ăn"))
        XCTAssertTrue(VietSyllable.hasVietnameseMarks("đi"))
        XCTAssertFalse(VietSyllable.hasVietnameseMarks("di"))
    }
}
