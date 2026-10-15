// Контракт с сервером (game/scripts/vscripts/osc): что лежит в net table
// osc_state и что приходит/уходит кастомными событиями. Поля описаны так, как
// их шлёт Lua; panorama-types сам превращает массивы в { [i]: ... }, а
// boolean — в 0 | 1 (NetworkedData).

interface OSCAbilityOption {
  name: string;
  label: string;
  rarity: string;
}

interface OSCShopItem {
  name: string;
  cost: number;
  stock: number; // -1 — без лимита
  max: number;
}

interface OSCRotationChoiceState {
  round: number;
  deadline: number;
  duration: number;
  options: OSCAbilityOption[];
  picked: string;
}

interface OSCVoteQuestion {
  id: string;
  options: string[];
  default: string;
}

interface OSCVoteState {
  open: number;
  questions: OSCVoteQuestion[];
  counts: Record<string, Record<string, number>>;
  result: Record<string, string>;
}

interface OSCSummaryRow {
  hero: string;
  rotations: number;
  kills: number;
  casino_net: number;
  chaos_damage: number;
}

interface OSCSummaryTitle {
  id: string;
  player_id: number;
  value: number;
}

interface OSCCasinoOutcome {
  symbol: string;
  multiplier: number;
  chance: number;
}

interface OSCCasinoResult {
  error?: string;
  min_stake?: number;
  gold?: number;
  reel1?: string;
  reel2?: string;
  reel3?: string;
  payout?: number;
  net?: number;
  stake?: number;
  multiplier?: number;
  items?: string; // "item_a,item_b"
}

// osc/systems/help.lua (OSC_Help.Build); флаги — 1/0
interface OSCHelpData {
  rotation: {
    interval: number;
    warning: number;
    choice_count: number;
    tag_streak: number;
    max_duplicate_ultimates: number;
  };
  rarity: {
    enabled: number;
    ability: Record<string, number>;
    ultimate: Record<string, number>;
  };
  anchor: { enabled: number; merge_count: number; levels: { name: string; cost: number }[] };
  chaos: {
    interval: number;
    warning: number;
    duration: number;
    events: { title_key: string; desc_key: string; params: Record<string, string | number> }[];
  };
  casino: {
    enabled: number;
    min_stake: number;
    lifetime: number;
    item_bets: number;
    item_value_pct: number;
    outcomes: OSCCasinoOutcome[];
  };
  sphere: { enabled: number; min_level: number; choices: number };
  couriers: {
    count: number;
    abilities: {
      name: string;
      name_token: string;
      duration: number;
      interval_min: number;
      interval_max: number;
    }[];
  };
  summary: { enabled: number; titles: string[]; ties: string };
}

interface CustomNetTableDeclarations {
  osc_state: {
    version: { version: string };
    timer: { next_rotation: number; interval: number };
    casino: { use_distance: number };
    chaos_round: {
      state: string;
      event_id: string;
      title_key: string;
      desc_key: string;
      desc_params: Record<string, string | number>;
      start_time: number;
      end_time: number;
    };
    help: OSCHelpData;
    summary: {
      players: Record<string, OSCSummaryRow>;
      titles: OSCSummaryTitle[];
    };
    vote: OSCVoteState;
    [key: `anchor_${number}`]: { active: number; rotations: number };
    [key: `shop_${number}`]: { items: OSCShopItem[] };
    [key: `choice_${number}`]: OSCRotationChoiceState;
    [key: `vote_${number}`]: Record<string, string>;
  };
}

interface CustomGameEventDeclarations {
  // сервер -> клиент
  osc_hud_error: { message: string };
  osc_ability_changed: { player_id: PlayerID; ability: string; label: string; rarity: string };
  osc_notification: { token: string; color?: string; params?: Record<string, string | number> };
  osc_shop_result: { ok: number; item: string; error?: string };
  osc_sphere_offer: { options: OSCAbilityOption[]; ultimate_allowed: number; min_level: number };
  osc_rotation_choice_offer: Omit<OSCRotationChoiceState, "picked">;
  osc_rotation_choice_closed: { round: number; chosen: string };
  osc_casino_open: {
    outcomes: OSCCasinoOutcome[];
    lose_chance: number;
    machine_entindex: EntityIndex;
    min_stake: number;
    default_stake: number;
    item_bets: boolean;
    item_value_factor: number;
    gold: number;
    lifetime: number;
    spinning: boolean;
  };
  osc_casino_result: OSCCasinoResult;
  osc_casino_closed: { machine_entindex: EntityIndex };

  // клиент -> сервер
  osc_shop_buy: { item: string };
  osc_sphere_pick: { mode: string; ability: string };
  osc_rotation_choice_pick: { round: number; ability: string };
  osc_casino_spin: { machine_entindex: EntityIndex; stake?: number; item_entindices?: string };
  osc_casino_reopen: { machine_entindex: EntityIndex; quiet: number };
  osc_vote_cast: { question: string; option: string };
  osc_team_shuffle: {};
}
