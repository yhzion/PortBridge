//! PortBridge CLI — portbridge-core 위에 구축되는 크로스 플랫폼 진입점.
//! 현재는 골격만 존재한다. 실제 서브커맨드는 후속 이슈(#3)에서 추가한다.

fn main() {
    println!("PortBridge CLI (core {})", portbridge_core::version());
}
