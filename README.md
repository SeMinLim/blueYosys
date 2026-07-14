# blueYosys

Bluespec 기반 하드웨어 가속기를 오픈소스 Yosys 계열 도구로 빌드하기 위한
멀티보드 저장소입니다. 현재 **Lattice ECP5 / ULX3S-85F**를 지원하며,
**ICE40**은 향후 포팅을 위한 명시적인 스캐폴드만 제공합니다.

## 핵심 변경

- 원본 `ulx3s_bsv`의 7개 `projects/` 설계를 데이터 파일까지 모두 유지합니다.
- 공통 라이브러리, FPGA 패밀리, 보드 계층을 `lib/`, `platforms/`,
  `boards/`로 분리했습니다.
- 중복된 프로젝트 Makefile을 `mk/project.mk` 하나로 통합했습니다.
- 잘못된 Makefile recipe와 누락된 `nn_fc_zfpe/Makefile`을 수정했습니다.
- `replacetoken`의 짧은 문자열 치환 시 정수 언더플로, 첫 항목만 치환하는
  문제, 잘못된 인자 처리, 메모리 해제 누락을 수정했습니다.
- 생성 바이너리는 커밋하지 않고 `make tools`로 재현합니다.
- 요청에 따라 `.gitignore`은 저장소에 두지 않습니다.

Upstream snapshot: `SeMinLim/ulx3s_bsv@a3652e203c2a4f78bc54bdbecd1eedc804d4eab4`

## 사용법

```sh
make list-projects
make lint
make synth PROJECT=test BOARD=ulx3s
make bsim PROJECT=matrix4x4 BOARD=ulx3s
make program PROJECT=test BOARD=ulx3s
```

필수 합성 도구는 Bluespec Compiler(`bsc`), APIO, Yosys/nextpnr-ecp5
툴체인입니다. 호스트 유틸리티 빌드에는 C/C++ 컴파일러가 필요합니다.

## 구조

```text
boards/       보드별 top, 주변장치, constraint, build metadata
lib/          디바이스 독립 Bluespec/C++ 라이브러리
platforms/    ECP5/ICE40 및 Bluespec runtime 계층
projects/     보존된 가속기/프로세서 설계 7종
mk/           공통 빌드 로직
scripts/      생성 Verilog 수정 및 저장소 검증
tools/        소스에서 재현되는 보조 도구
src/          기존 경로 호환용 symbolic-link facade
```

세부 설계 원칙은 `docs/architecture.md`, 새 보드 추가 절차는
`docs/adding-a-board.md`를 참고하십시오.
