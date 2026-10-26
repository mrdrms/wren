import Foundation
import Testing
@testable import writer

struct SecurityTests {
    @Test func findsCommonSecrets() {
        let text = """
        # Incident write-up

        The attacker used AKIAIOSFODNN7EXAMPLE from a leaked config.
        password = "hunter2hunter2"
        The jump box was 10.0.12.7, not the public 8.8.8.8.
        -----BEGIN RSA PRIVATE KEY-----
        """
        let kinds = SecretScanner.scan(text).map(\.kind)
        #expect(kinds == ["AWS access key", "Password or secret", "Internal IP address", "Private key"])
        #expect(SecretScanner.scan(text).first?.line == 3)
        #expect(SecretScanner.scan(text).first?.preview == "AKIA…MPLE")
    }

    @Test func ordinaryProseIsClean() {
        #expect(SecretScanner.scan("I reset my password yesterday. The token economy is complex. Version 10.4 ships soon.").isEmpty)
    }

    @Test func candlelightBecomesTerminal() {
        #expect(Theme.named("sepia").id == "terminal")
        #expect(Theme.named("terminal").font == .mono)
        #expect(BlogStyle.terminal.css().contains("user@wren:~$ cat post.md"))
    }
}
