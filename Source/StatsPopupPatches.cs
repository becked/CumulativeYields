using System;
using System.Collections;
using System.Collections.Generic;
using System.Reflection;
using HarmonyLib;
using Mohawk.UIInterfaces;
using TenCrowns.ClientCore;
using TenCrowns.GameCore;
using TenCrowns.GameCore.Text;
using UnityEngine;

namespace CumulativeYields
{
    internal static class StatsPopupPatches
    {
        // --- Constants ---
        internal const int TOTALS_OFFSET = 100;
        internal const int PRODUCTION_TAB = 1;  // PopupTabType.PRODUCTION
        internal const int STATS_TAB = 0;       // PopupTabType.STATS

        // --- Shared state ---
        internal static readonly Dictionary<int, int> DataValueToUIIndex = new Dictionary<int, int>();

        [ThreadStatic] internal static bool IsTotalsGraph;
        [ThreadStatic] internal static int SavedSubTab;
        [ThreadStatic] internal static bool IsTooltipForTotals;
        [ThreadStatic] internal static YieldType CurrentTotalsYield;

        // --- Cached reflection ---
        static MethodInfo _shouldShowPlayer;
        static MethodInfo _updateGraphTitle;
        static Type _statsPopupType;

        // --- Initialization ---
        internal static void Initialize(Type statsPopupType)
        {
            _statsPopupType = statsPopupType;

            // StatsPopup methods (in Assembly-CSharp, must use reflection)
            _shouldShowPlayer = AccessTools.Method(statsPopupType, "ShouldShowPlayer");
            _updateGraphTitle = AccessTools.Method(statsPopupType, "UpdateGraphTitle");

            Debug.Log("[CumulativeYields] Reflection cache initialized.");
        }

        // --- Instance field helpers ---
        static Traverse T(object instance) => Traverse.Create(instance);

        static int GetCurrentTab(object instance) => T(instance).Field("currentTab").GetValue<int>();
        static int GetCurrentSubTab(object instance) => T(instance).Field("currentSubTab").GetValue<int>();
        static void SetCurrentSubTab(object instance, int value) => T(instance).Field("currentSubTab").SetValue(value);
        static UIAttributeTag GetPopupTag(object instance) => T(instance).Field("popupTag").GetValue<UIAttributeTag>();
        static IList GetLineData(object instance) => T(instance).Field("lineData").GetValue<IList>();

        static Game GetGame(object instance) => T(instance).Property("mGame").GetValue<Game>();
        static Infos GetInfos(object instance) => T(instance).Property("mInfos").GetValue<Infos>();
        static HelpText GetHelpText(object instance) => T(instance).Property("helpText").GetValue<HelpText>();
        static TextManager GetTextManager(object instance) => T(instance).Property("textManager").GetValue<TextManager>();
        static Player GetActivePlayer(object instance) => T(instance).Property("pActivePlayer").GetValue<Player>();

        static bool ShouldShowPlayer(object instance, Player player)
        {
            return (bool)_shouldShowPlayer.Invoke(instance, new object[] { player });
        }

        // --- Encoding helpers ---
        static bool IsTotals(int subTab) => subTab >= TOTALS_OFFSET;
        static YieldType DecodeYield(int subTab) => (YieldType)(subTab % TOTALS_OFFSET);
        static int GetUIIndex(int dataValue)
        {
            return DataValueToUIIndex.TryGetValue(dataValue, out int idx) ? idx : dataValue;
        }

        // ================================================================
        // PATCH 1: UpdateLabels — Prefix, skip original
        // ================================================================
        public static bool UpdateLabels_Prefix(object __instance)
        {
            try
            {
                UIAttributeTag popupTag = GetPopupTag(__instance);
                TextManager textMgr = GetTextManager(__instance);
                HelpText helpText = GetHelpText(__instance);
                Infos infos = GetInfos(__instance);

                if (popupTag == null || textMgr == null || helpText == null || infos == null)
                    return true; // fall through to original

                // --- PRODUCTION category (index 0) ---
                UIAttributeTag catTag = popupTag.GetSubTag("-Category", 0);
                catTag.SetKey("Title", textMgr.TEXT("TEXT_UI_GRAPHS_PRODUCTION"));

                int num = 0;
                DataValueToUIIndex.Clear();

                for (YieldType yieldType = (YieldType)0; yieldType < infos.yieldsNum(); yieldType++)
                {
                    InfoYield yieldInfo = infos.yield(yieldType);
                    if (yieldInfo.meSubtractFromYield != YieldType.NONE || yieldInfo.mbHideOnUI)
                        continue;

                    TextVariable yieldVar = helpText.buildYieldLinkVariable(yieldType, false);

                    // Rate sub-tab
                    UIAttributeTag rateTag = catTag.GetSubTag("-Graph", num);
                    string rateTitle = textMgr.TEXT("TEXT_CUMULATIVE_YIELDS_SUB_RATE", yieldVar);
                    rateTag.SetKey("Title", rateTitle);
                    int rateDataValue = (int)yieldType;
                    rateTag.SetKey("Data", "1," + rateDataValue);
                    DataValueToUIIndex[rateDataValue] = num;
                    num++;

                    // Totals sub-tab
                    UIAttributeTag totalTag = catTag.GetSubTag("-Graph", num);
                    string totalTitle = textMgr.TEXT("TEXT_CUMULATIVE_YIELDS_SUB_TOTAL", yieldVar);
                    totalTag.SetKey("Title", totalTitle);
                    int totalDataValue = (int)yieldType + TOTALS_OFFSET;
                    totalTag.SetKey("Data", "1," + totalDataValue);
                    DataValueToUIIndex[totalDataValue] = num;
                    num++;
                }

                catTag.SetInt("NumSubGraphs", num);

                // --- Standalone graph tab labels (MILITARY through RELIGIONS) ---
                // PopupTabType: MILITARY=2, TERRITORY=3, EXPLORATION=4, PRICES=5,
                //               POINTS=6, LEGITIMACY=7, FAMILIES=8, RELIGIONS=9
                string[] tabNames = { null, null, "MILITARY", "TERRITORY", "EXPLORATION",
                                      "PRICES", "POINTS", "LEGITIMACY", "FAMILIES", "RELIGIONS" };
                for (int tab = 2; tab < tabNames.Length; tab++)
                {
                    if (tabNames[tab] != null)
                    {
                        UIAttributeTag graphTag = popupTag.GetSubTag("-Graph", tab);
                        graphTag.SetKey("Title", textMgr.TEXT("TEXT_UI_GRAPHS_" + tabNames[tab]));
                    }
                }

                return false; // skip original
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] UpdateLabels_Prefix error: {ex}");
                return true;
            }
        }

        // ================================================================
        // PATCH 2: OnWidgetClicked — Prefix, conditional skip
        // ================================================================
        public static bool OnWidgetClicked_Prefix(object __instance, WidgetData data, ref bool __result)
        {
            try
            {
                // Check widget type via string comparison (WidgetData.Type)
                string widgetType = data.Type;
                if (widgetType != "ItemType.STATS_SCREEN_TAB" && widgetType != "STATS_SCREEN_TAB")
                    return true; // not a tab click, let original handle

                // Read click data from WidgetData string fields
                int newTab = -1;
                if (!string.IsNullOrEmpty(data[0]))
                    int.TryParse(data[0], out newTab);
                int newSubTab = -1;
                if (data.DataCount > 1 && !string.IsNullOrEmpty(data[1]))
                {
                    int.TryParse(data[1], out newSubTab);
                }

                Traverse t = T(__instance);
                int oldTab = t.Field("currentTab").GetValue<int>();
                int oldSubTab = t.Field("currentSubTab").GetValue<int>();

                if (newTab == oldTab && newSubTab == oldSubTab)
                {
                    __result = true;
                    return false;
                }

                UIAttributeTag popupTag = t.Field("popupTag").GetValue<UIAttributeTag>();

                // Deselect old sub-tab
                if (oldTab != -1) // NONE = -1
                {
                    if (oldTab == PRODUCTION_TAB)
                    {
                        int oldUIIndex = GetUIIndex(oldSubTab);
                        UIAttributeTag oldCatTag = popupTag.GetSubTag("-Category", oldTab);
                        UIAttributeTag oldGraphTag = oldCatTag.GetSubTag("-Graph", oldUIIndex);
                        oldGraphTag.SetKey("State", "Normal");
                    }
                    else if (oldTab > STATS_TAB)
                    {
                        UIAttributeTag oldGraphTag = popupTag.GetSubTag("-Graph", oldTab);
                        oldGraphTag.SetKey("State", "Normal");
                    }
                }

                // Update state
                // Set currentTab via reflection (it's an enum, need to cast)
                Type popupTabType = t.Field("currentTab").GetValueType();
                t.Field("currentTab").SetValue(Enum.ToObject(popupTabType, newTab));
                t.Field("currentSubTab").SetValue(newSubTab);
                t.Field("isPopupDirty").SetValue(true);

                // Update graph title
                _updateGraphTitle.Invoke(__instance, null);

                // Select new sub-tab
                if (newTab == PRODUCTION_TAB)
                {
                    int newUIIndex = GetUIIndex(newSubTab);
                    UIAttributeTag newCatTag = popupTag.GetSubTag("-Category", newTab);
                    UIAttributeTag newGraphTag = newCatTag.GetSubTag("-Graph", newUIIndex);
                    newGraphTag.SetKey("State", "Selected");
                }
                else if (newTab > STATS_TAB)
                {
                    UIAttributeTag newGraphTag = popupTag.GetSubTag("-Graph", newTab);
                    newGraphTag.SetKey("State", "Selected");
                }

                popupTag.SetInt("CurrentTab", newTab);

                // Clear line data for fresh rebuild
                IList lineData = t.Field("lineData").GetValue<IList>();
                lineData.Clear();

                __result = true;
                return false; // skip original
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] OnWidgetClicked_Prefix error: {ex}");
                return true;
            }
        }

        // ================================================================
        // PATCH 3a: UpdateGraph(PopupTabType) — Prefix (does NOT skip)
        // ================================================================
        public static void UpdateGraphTab_Prefix(object __instance)
        {
            try
            {
                Traverse t = T(__instance);
                int currentTab = t.Field("currentTab").GetValue<int>();

                if (currentTab != PRODUCTION_TAB)
                {
                    IsTotalsGraph = false;
                    return;
                }

                int currentSubTab = t.Field("currentSubTab").GetValue<int>();

                if (currentSubTab >= TOTALS_OFFSET)
                {
                    SavedSubTab = currentSubTab;
                    CurrentTotalsYield = DecodeYield(currentSubTab);
                    IsTotalsGraph = true;

                    // Temporarily set to decoded yield so the original's
                    // (YieldType)currentSubTab cast resolves correctly
                    Type popupTabType = t.Field("currentTab").GetValueType();
                    t.Field("currentSubTab").SetValue(currentSubTab - TOTALS_OFFSET);
                }
                else
                {
                    IsTotalsGraph = false;
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] UpdateGraphTab_Prefix error: {ex}");
                IsTotalsGraph = false;
            }
        }

        // ================================================================
        // PATCH 3b: UpdateGraph(PopupTabType) — Postfix
        // ================================================================
        public static void UpdateGraphTab_Postfix(object __instance)
        {
            try
            {
                if (IsTotalsGraph)
                {
                    T(__instance).Field("currentSubTab").SetValue(SavedSubTab);
                    IsTotalsGraph = false;
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] UpdateGraphTab_Postfix error: {ex}");
            }
        }

        // ================================================================
        // PATCH 3c: UpdateGraph(Func<Player, int, float>) — Prefix (does NOT skip)
        // ================================================================
        public static void UpdateGraphFunc_Prefix(ref Func<Player, int, float> valueFunc)
        {
            try
            {
                if (IsTotalsGraph)
                {
                    YieldType eYield = CurrentTotalsYield;
                    valueFunc = (Player player, int turn) =>
                        (float)player.getTurnYieldTotal(turn, eYield);
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] UpdateGraphFunc_Prefix error: {ex}");
            }
        }

        // ================================================================
        // PATCH 4: UpdateGraphTitle — Prefix, skip original
        // ================================================================
        public static bool UpdateGraphTitle_Prefix(object __instance)
        {
            try
            {
                Traverse t = T(__instance);
                int currentTab = t.Field("currentTab").GetValue<int>();
                int currentSubTab = t.Field("currentSubTab").GetValue<int>();
                UIAttributeTag popupTag = t.Field("popupTag").GetValue<UIAttributeTag>();
                TextManager textMgr = GetTextManager(__instance);
                HelpText helpText = GetHelpText(__instance);

                if (popupTag == null || textMgr == null || helpText == null)
                    return true;

                if (currentTab == PRODUCTION_TAB)
                {
                    bool isTotals = IsTotals(currentSubTab);
                    YieldType eYield = DecodeYield(currentSubTab);
                    TextVariable yieldVar = helpText.buildYieldLinkVariable(eYield, false);

                    string title = isTotals
                        ? textMgr.TEXT("TEXT_CUMULATIVE_YIELDS_TITLE_TOTAL", yieldVar)
                        : textMgr.TEXT("TEXT_CUMULATIVE_YIELDS_TITLE_RATE", yieldVar);

                    popupTag.SetKey("CurrentGraph-Title", title);
                }
                else
                {
                    // Replicate original for non-PRODUCTION tabs
                    object currentTabObj = t.Field("currentTab").GetValue();
                    string tabName = currentTabObj.ToString();
                    popupTag.SetKey("CurrentGraph-Title",
                        textMgr.TEXT("TEXT_UI_GRAPHS_" + tabName));
                }

                return false; // skip original
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] UpdateGraphTitle_Prefix error: {ex}");
                return true;
            }
        }

        // ================================================================
        // PATCH 5: buildGraphTooltip — Prefix (does NOT skip)
        // ================================================================
        public static void BuildGraphTooltip_Prefix(ref int iExtraData)
        {
            try
            {
                if (iExtraData >= TOTALS_OFFSET)
                {
                    IsTooltipForTotals = true;
                    iExtraData -= TOTALS_OFFSET;
                }
                else
                {
                    IsTooltipForTotals = false;
                }
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] BuildGraphTooltip_Prefix error: {ex}");
            }
        }

        // ================================================================
        // PATCH 6: buildGraphHelp — Prefix, conditional skip
        // ================================================================
        public static bool BuildGraphHelp_Prefix()
        {
            // No custom tooltip behavior — let the original run for both
            // rate and cumulative charts (Patch 5 fixes the yield type)
            return true;
        }
    }
}
