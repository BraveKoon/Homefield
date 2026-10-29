import Foundation

/// 계정·동기화 서버 (Supabase). 설정 순서는 docs/sync-setup.md 에 있다.
enum SupabaseConfig {
    static let url = URL(string: "https://lljdjedvrpebkscaxzkh.supabase.co")!
    /// anon 키는 앱에 들어가는 공개 값이다. 데이터는 행 단위 보안(RLS)이 지킨다.
    /// service_role 키는 절대 여기에 넣지 않는다.
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxsamRqZWR2cnBlYmtzY2F4emtoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyOTg2MTEsImV4cCI6MjEwODg3NDYxMX0.sEGX7APKB5CY2bJpTCtOOqJVKpAgSz_u0PULFt3z8FM"
}
