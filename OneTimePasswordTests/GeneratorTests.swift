//
//  GeneratorTests.swift
//  OneTimePassword
//
//  Created by Matt Rubin on 7/9/14.
//  Copyright (c) 2014 Matt Rubin. All rights reserved.
//

import XCTest
import OneTimePassword

class GeneratorTests: XCTestCase {
    func testInit() {
        // Create a generator
        let factor = OneTimePassword.Generator.Factor.Counter(111)
        let secret = "12345678901234567890".dataUsingEncoding(NSASCIIStringEncoding)!
        let algorithm = Generator.Algorithm.SHA256
        let digits = 8

        let generator = Generator(
            factor: factor,
            secret: secret,
            algorithm: algorithm,
            digits: digits
        )

        XCTAssertEqual(generator?.factor, factor)
        XCTAssertEqual(generator?.secret, secret)
        XCTAssertEqual(generator?.algorithm, algorithm)
        XCTAssertEqual(generator?.digits, digits)

        // Create another generator
        let other_factor = OneTimePassword.Generator.Factor.Timer(period: 123)
        let other_secret = "09876543210987654321".dataUsingEncoding(NSASCIIStringEncoding)!
        let other_algorithm = Generator.Algorithm.SHA512
        let other_digits = 7

        let other_generator = Generator(
            factor: other_factor,
            secret: other_secret,
            algorithm: other_algorithm,
            digits: other_digits
        )

        XCTAssertEqual(other_generator?.factor, other_factor)
        XCTAssertEqual(other_generator?.secret, other_secret)
        XCTAssertEqual(other_generator?.algorithm, other_algorithm)
        XCTAssertEqual(other_generator?.digits, other_digits)

        // Ensure the generators are different
        XCTAssertNotEqual(generator?.factor, other_generator?.factor)
        XCTAssertNotEqual(generator?.secret, other_generator?.secret)
        XCTAssertNotEqual(generator?.algorithm, other_generator?.algorithm)
        XCTAssertNotEqual(generator?.digits, other_generator?.digits)
    }

    func testCounter() {
        let factors: [(NSTimeInterval, NSTimeInterval, UInt64)] = [
            (30,    100,            3),
            (30,    10000,          333),
            (30,    1000000,        33333),
            (60,    100000000,      1666666),
            (90,    10000000000,    111111111),
        ]

        for (period, time, counter) in factors {
            let secret = "12345678901234567890".dataUsingEncoding(NSASCIIStringEncoding)!
            let counterPassword = Generator(
                factor: .Counter(counter),
                secret: secret,
                algorithm: .SHA1,
                digits: 6)
                .flatMap { try? $0.passwordAtTime(time) }
            let timerPassword = Generator(
                factor: .Timer(period: period),
                secret: secret,
                algorithm: .SHA1,
                digits: 6
                )
                .flatMap { try? $0.passwordAtTime(time) }
            XCTAssertEqual(counterPassword, timerPassword, "TOTP with period \(period) should " +
                "match HOTP with counter \(counter) at time \(time).")
        }
    }

    func testValidation() {
        let digitTests: [(Int, Bool)] = [
            (-6, false),
            (0, false),
            (1, false),
            (5, false),
            (6, true),
            (7, true),
            (8, true),
            (9, false),
            (10, false),
        ]

        let periodTests: [(NSTimeInterval, Bool)] = [
            (-30, false),
            (0, false),
            (1, true),
            (30, true),
            (300, true),
            (301, true),
        ]

        for (digits, digitsAreValid) in digitTests {
            let generator = Generator(
                factor: .Counter(0),
                secret: NSData(),
                algorithm: .SHA1,
                digits: digits
            )
            // If the digits are invalid, password generation should throw an error
            let generatorIsValid = digitsAreValid
            if generatorIsValid {
                XCTAssertNotNil(generator)
            } else {
                XCTAssertNil(generator)
            }

            for (period, periodIsValid) in periodTests {
                let generator = Generator(
                    factor: .Timer(period: period),
                    secret: NSData(),
                    algorithm: .SHA1,
                    digits: digits
                )
                // If the digits or period are invalid, password generation should throw an error
                let generatorIsValid = digitsAreValid && periodIsValid
                if generatorIsValid {
                    XCTAssertNotNil(generator)
                } else {
                    XCTAssertNil(generator)
                }
            }
        }
    }

    // The values in this test are found in Appendix D of the HOTP RFC
    // https://tools.ietf.org/html/rfc4226#appendix-D
    func testHOTPRFCValues() {
        let secret = "12345678901234567890".dataUsingEncoding(NSASCIIStringEncoding)!
        let expectedValues: [UInt64: String] = [
            0: "755224",
            1: "287082",
            2: "359152",
            3: "969429",
            4: "338314",
            5: "254676",
            6: "287922",
            7: "162583",
            8: "399871",
            9: "520489",
        ]
        for (counter, expectedPassword) in expectedValues {
            let generator = Generator(factor: .Counter(counter), secret: secret, algorithm: .SHA1, digits: 6)
            let password = generator.flatMap { try? $0.passwordAtTime(0) }
            XCTAssertEqual(password, expectedPassword,
                "The generator did not produce the expected OTP.")
        }
    }

    // The values in this test are found in Appendix B of the TOTP RFC
    // https://tools.ietf.org/html/rfc6238#appendix-B
    func testTOTPRFCValues() {
        let secretKeys: [Generator.Algorithm: String] = [
            .SHA1:   "12345678901234567890",
            .SHA256: "12345678901234567890123456789012",
            .SHA512: "1234567890123456789012345678901234567890123456789012345678901234",
        ]

        let times: [NSTimeInterval] = [59, 1111111109, 1111111111, 1234567890, 2000000000, 20000000000]

        let expectedValues: [Generator.Algorithm: [String]] = [
            .SHA1:   ["94287082", "07081804", "14050471", "89005924", "69279037", "65353130"],
            .SHA256: ["46119246", "68084774", "67062674", "91819424", "90698825", "77737706"],
            .SHA512: ["90693936", "25091201", "99943326", "93441116", "38618901", "47863826"],
        ]

        for (algorithm, secretKey) in secretKeys {
            let secret = secretKey.dataUsingEncoding(NSASCIIStringEncoding)!
            let generator = Generator(factor: .Timer(period: 30), secret: secret, algorithm: algorithm, digits: 8)

            for i in 0..<times.count {
                let expectedPassword = expectedValues[algorithm]?[i]
                let time = times[i]
                let password = generator.flatMap { try? $0.passwordAtTime(time) }
                XCTAssertEqual(password, expectedPassword,
                    "Incorrect result for \(algorithm) at \(times[i])")
            }
        }
    }

    // From Google Authenticator for iOS
    // https://code.google.com/p/google-authenticator/source/browse/mobile/ios/Classes/TOTPGeneratorTest.m
    func testTOTPGoogleValues() {
        let secret = "12345678901234567890".dataUsingEncoding(NSASCIIStringEncoding)!
        let times: [NSTimeInterval] = [1111111111, 1234567890, 2000000000]

        let expectedValues: [Generator.Algorithm: [String]] = [
            .SHA1:   ["050471", "005924", "279037"],
            .SHA256: ["584430", "829826", "428693"],
            .SHA512: ["380122", "671578", "464532"],
        ]

        for (algorithm, expectedPasswords) in expectedValues {
            let generator = Generator(factor: .Timer(period: 30), secret: secret, algorithm: algorithm, digits: 6)
            for i in 0..<times.count {
                let expectedPassword = expectedPasswords[i]
                let time = times[i]
                let password = generator.flatMap { try? $0.passwordAtTime(time) }
                XCTAssertEqual(password, expectedPassword,
                    "Incorrect result for \(algorithm) at \(times[i])")
            }
        }
    }
}
