using System;
using System.Linq;
using System.Reflection;
using HarmonyLib;
using TenCrowns.AppCore;
using TenCrowns.GameCore;
using UnityEngine;

namespace CumulativeYields
{
    public class ModEntryPoint : ModEntryPointAdapter
    {
        private const string HarmonyId = "com.cumulative-yields";
        private static Harmony _harmony;

        public override void Initialize(ModSettings modSettings)
        {
            base.Initialize(modSettings);

            if (_harmony != null) return; // Triple-load guard

            try
            {
                _harmony = new Harmony(HarmonyId);
                ApplyPatches();
                Debug.Log("[CumulativeYields] Harmony patches applied successfully.");
            }
            catch (Exception ex)
            {
                Debug.LogError($"[CumulativeYields] Failed to apply patches: {ex}");
            }
        }

        public override void Shutdown()
        {
            _harmony?.UnpatchAll(HarmonyId);
            _harmony = null;
            Debug.Log("[CumulativeYields] Harmony patches removed.");
            base.Shutdown();
        }

        private void ApplyPatches()
        {
            Type statsPopupType = AccessTools.TypeByName("StatsPopup");
            if (statsPopupType == null)
            {
                Debug.LogError("[CumulativeYields] Could not find StatsPopup type.");
                return;
            }

            StatsPopupPatches.Initialize(statsPopupType);

            var allMethods = statsPopupType.GetMethods(
                BindingFlags.Instance | BindingFlags.NonPublic | BindingFlags.Public);

            // Patch 1: UpdateLabels — prefix, skip original
            MethodInfo updateLabels = allMethods.FirstOrDefault(
                m => m.Name == "UpdateLabels" && m.GetParameters().Length == 0);
            if (updateLabels != null)
            {
                _harmony.Patch(updateLabels,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.UpdateLabels_Prefix)));
                Debug.Log("[CumulativeYields] Patched UpdateLabels");
            }
            else Debug.LogError("[CumulativeYields] Could not find UpdateLabels");

            // Patch 2: OnWidgetClicked — prefix, conditional skip
            MethodInfo onWidgetClicked = allMethods.FirstOrDefault(
                m => m.Name == "OnWidgetClicked" && m.GetParameters().Length == 1);
            if (onWidgetClicked != null)
            {
                _harmony.Patch(onWidgetClicked,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.OnWidgetClicked_Prefix)));
                Debug.Log("[CumulativeYields] Patched OnWidgetClicked");
            }
            else Debug.LogError("[CumulativeYields] Could not find OnWidgetClicked");

            // Patch 3a/3b: UpdateGraph(PopupTabType) — prefix + postfix
            MethodInfo updateGraphTab = allMethods.FirstOrDefault(
                m => m.Name == "UpdateGraph"
                     && m.GetParameters().Length == 1
                     && m.GetParameters()[0].ParameterType.Name == "PopupTabType");
            if (updateGraphTab != null)
            {
                _harmony.Patch(updateGraphTab,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.UpdateGraphTab_Prefix)),
                    postfix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.UpdateGraphTab_Postfix)));
                Debug.Log("[CumulativeYields] Patched UpdateGraph(PopupTabType)");
            }
            else Debug.LogError("[CumulativeYields] Could not find UpdateGraph(PopupTabType)");

            // Patch 3c: UpdateGraph(Func<Player, int, float>) — prefix
            MethodInfo updateGraphFunc = allMethods.FirstOrDefault(
                m => m.Name == "UpdateGraph"
                     && m.GetParameters().Length == 1
                     && m.GetParameters()[0].ParameterType.Name.StartsWith("Func"));
            if (updateGraphFunc != null)
            {
                _harmony.Patch(updateGraphFunc,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.UpdateGraphFunc_Prefix)));
                Debug.Log("[CumulativeYields] Patched UpdateGraph(Func)");
            }
            else Debug.LogError("[CumulativeYields] Could not find UpdateGraph(Func)");

            // Patch 4: UpdateGraphTitle — prefix, skip original
            MethodInfo updateGraphTitle = allMethods.FirstOrDefault(
                m => m.Name == "UpdateGraphTitle" && m.GetParameters().Length == 0);
            if (updateGraphTitle != null)
            {
                _harmony.Patch(updateGraphTitle,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.UpdateGraphTitle_Prefix)));
                Debug.Log("[CumulativeYields] Patched UpdateGraphTitle");
            }
            else Debug.LogError("[CumulativeYields] Could not find UpdateGraphTitle");

            // Patch 5: buildGraphTooltip — prefix (does not skip)
            MethodInfo buildGraphTooltip = allMethods.FirstOrDefault(
                m => m.Name == "buildGraphTooltip");
            if (buildGraphTooltip != null)
            {
                _harmony.Patch(buildGraphTooltip,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.BuildGraphTooltip_Prefix)));
                Debug.Log("[CumulativeYields] Patched buildGraphTooltip");
            }
            else Debug.LogError("[CumulativeYields] Could not find buildGraphTooltip");

            // Patch 6: buildGraphHelp — prefix, conditional skip
            MethodInfo buildGraphHelp = allMethods.FirstOrDefault(
                m => m.Name == "buildGraphHelp");
            if (buildGraphHelp != null)
            {
                _harmony.Patch(buildGraphHelp,
                    prefix: new HarmonyMethod(typeof(StatsPopupPatches),
                        nameof(StatsPopupPatches.BuildGraphHelp_Prefix)));
                Debug.Log("[CumulativeYields] Patched buildGraphHelp");
            }
            else Debug.LogError("[CumulativeYields] Could not find buildGraphHelp");

            Debug.Log("[CumulativeYields] All patches registered.");
        }
    }
}
