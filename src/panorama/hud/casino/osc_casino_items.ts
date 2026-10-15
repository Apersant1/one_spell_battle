namespace OSC.Casino {
  // Казино: чтение инвентаря для ставки предметами и названия предметов в итоге.
  // factor — доля цены, которую стоит предмет (как при продаже).

  // name и value запоминаются при чтении инвентаря: проигранные предметы сервер
  // удаляет сразу, а окно ещё перерисовывается, пока крутятся барабаны
  export type InventorySlot = {
    item: ItemEntityIndex | -1;
    reason: string;
    name: string;
    value: number;
  };

  function GetItemValue(item: ItemEntityIndex, factor: number) {
    return Math.floor(Items.GetCost(item) * factor);
  }

  // Ключ локализации причины, по которой предмет нельзя поставить (то же, что
  // проверяет сервер), или ""
  function GetItemRejectReason(item: ItemEntityIndex, hero: EntityIndex, factor: number) {
    if (!Items.IsSellable(item) || GetItemValue(item, factor) <= 0)
      return "osc_casino_err_item_unsellable";
    if (Items.GetPurchaser(item) !== hero) return "osc_casino_err_item_not_yours";
    return "";
  }

  // Шесть слотов основного инвентаря; item -1 — слот пуст
  export function GetInventorySlots(factor: number) {
    var hero = Players.GetPlayerHeroEntityIndex(Players.GetLocalPlayer());
    var result: InventorySlot[] = [];
    for (var slot = 0; slot < 6; slot++) {
      var item: ItemEntityIndex | -1 =
        hero === undefined || hero === -1 ? -1 : Entities.GetItemInSlot(hero, slot);
      if (item === undefined) item = -1;
      result.push({
        item: item,
        reason: item === -1 ? "" : GetItemRejectReason(item, hero, factor),
        name: item === -1 ? "" : Abilities.GetAbilityName(item),
        value: item === -1 ? 0 : GetItemValue(item, factor),
      });
    }
    return result;
  }

  // Названия предметов из ответа сервера ("item_a,item_b") через запятую
  // Одинаковые предметы схлопываются: «Javelin ×3, Blades of Attack»
  export function LocalizeItemList(names: string) {
    var order: string[] = [];
    var counts: Record<string, number> = {};
    String(names)
      .split(",")
      .forEach(function (name) {
        if (!counts[name]) order.push(name);
        counts[name] = (counts[name] || 0) + 1;
      });
    return order
      .map(function (name) {
        var title = $.Localize("#DOTA_Tooltip_Ability_" + name);
        return counts[name] > 1 ? title + " ×" + counts[name] : title;
      })
      .join(", ");
  }
}
