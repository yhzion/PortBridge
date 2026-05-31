// `#[tauri::command]` 백엔드 표면(src-tauri/src/commands.rs)을 감싸는 타입드 invoke 래퍼.
//
// 커맨드명 = Rust fn명(snake_case). 인자 키 = Rust 파라미터명(전부 단일 단어라 케이스 변환 무관).
// 반환 타입은 백엔드 DTO(types.ts)와 정렬. 에러는 Rust가 `Result<_, String>`을 reject로 던지므로
// 호출부(store)에서 try/catch로 ErrorToast로 환원한다.

import { invoke } from "@tauri-apps/api/core";

import type {
  Favorite,
  Forwarding,
  ForwardSpec,
  Prefs,
  RemotePort,
  ResolvedHost,
  Server,
} from "./types";

/** core 버전 문자열 (아키텍처 검증용). */
export const coreVersion = (): Promise<string> =>
  invoke<string>("core_version");

/** 원격 서버 수신 포트 스캔. */
export const scanPorts = (server: Server): Promise<RemotePort[]> =>
  invoke<RemotePort[]>("scan_ports", { server });

/** ~/.ssh/config의 Host alias 해석. */
export const resolveAlias = (alias: string): Promise<ResolvedHost | null> =>
  invoke<ResolvedHost | null>("resolve_alias", { alias });

/** 저장된 서버 목록. */
export const serverList = (): Promise<Server[]> =>
  invoke<Server[]>("server_list");

/** 서버 목록 전체 저장(호출자가 (역)직렬화 책임). */
export const serverSave = (servers: Server[]): Promise<void> =>
  invoke<void>("server_save", { servers });

/** 즐겨찾기 목록. */
export const favoritesList = (): Promise<Favorite[]> =>
  invoke<Favorite[]>("favorites_list");

/** 즐겨찾기 전체 저장. */
export const favoritesSave = (favorites: Favorite[]): Promise<void> =>
  invoke<void>("favorites_save", { favorites });

/** 환경설정 로드(부재 시 기본값). */
export const prefsLoad = (): Promise<Prefs> => invoke<Prefs>("prefs_load");

/** 환경설정 저장. */
export const prefsSave = (prefs: Prefs): Promise<void> =>
  invoke<void>("prefs_save", { prefs });

/** 터널 시작 — settle 후 살아남으면 활성 레지스트리 등록 + 메타 반환. */
export const forwardingStart = (
  server: Server,
  spec: ForwardSpec,
): Promise<Forwarding> =>
  invoke<Forwarding>("forwarding_start", { server, spec });

/** id의 터널 종료. */
export const forwardingStop = (id: string): Promise<void> =>
  invoke<void>("forwarding_stop", { id });

/** 현재 활성 터널 목록. */
export const forwardingList = (): Promise<Forwarding[]> =>
  invoke<Forwarding[]>("forwarding_list");

/** ssh 실행 없이 forward argv만 조립(캐노니컬 형태 검증/디버그용). */
export const forwardArgsPreview = (
  server: Server,
  spec: ForwardSpec,
): Promise<string[]> =>
  invoke<string[]>("forward_args_preview", { server, spec });
