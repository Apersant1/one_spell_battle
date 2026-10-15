namespace OSC {
  export const AbilityPopup = (function () {
    var FLIP_DURATION = 0.15; // совпадает с transition-duration у #PopupCard
    var FLASH_HOLD = 0.05;
    var SHOW_DURATION = 2.5;

    var hideHandle: ScheduleID | null = null;
    var flipHandle: ScheduleID | null = null;
    var flashHandle: ScheduleID | null = null;

    function Flash() {
      var flash = $("#PopupFlash");
      flash.AddClass("Flash");
      if (flashHandle !== null) $.CancelScheduled(flashHandle);
      flashHandle = $.Schedule(FLASH_HOLD, function () {
        flashHandle = null;
        flash.RemoveClass("Flash");
      });
    }

    // Имя способности из локализации Dota; если ключа нет — подпись из пула
    function AbilityDisplayName(event: NetworkedData<CustomGameEventDeclarations["osc_ability_changed"]>) {
      var token = "#DOTA_Tooltip_Ability_" + event.ability;
      var localized = $.Localize(token);
      return localized && localized !== token ? localized : event.label;
    }

    function OnAbilityChanged(event: NetworkedData<CustomGameEventDeclarations["osc_ability_changed"]>) {
      if (Number(event.player_id) !== Players.GetLocalPlayer()) return;

      var popup = $("#Popup");
      var card = $("#PopupCard");

      popup.AddClass("Visible");
      card.AddClass("FlipHidden"); // старая иконка уходит ребром

      if (flipHandle !== null) $.CancelScheduled(flipHandle);
      flipHandle = $.Schedule(FLIP_DURATION, function () {
        flipHandle = null;
        ($("#PopupIcon") as AbilityImage).abilityname = event.ability;
        ($("#PopupTitle") as LabelPanel).text = $.Localize("#osc_hud_popup_title");
        ($("#PopupName") as LabelPanel).text = AbilityDisplayName(event);
        card.RemoveClass("FlipHidden"); // новая разворачивается
        Flash();
        card.SetHasClass("RarityRare", event.rarity === "rare");
        card.SetHasClass("RarityLegendary", event.rarity === "legendary");
        OSC.Util.PlaySound(
          event.rarity === "legendary" ? OSC.Sounds.legendaryAbility : OSC.Sounds.abilityChanged,
        );
      });

      if (hideHandle !== null) $.CancelScheduled(hideHandle);
      hideHandle = $.Schedule(SHOW_DURATION, function () {
        hideHandle = null;
        popup.RemoveClass("Visible");
      });
    }

    function Init() {
      GameEvents.Subscribe("osc_ability_changed", OnAbilityChanged);
    }

    return { Init: Init };
  })();
}
