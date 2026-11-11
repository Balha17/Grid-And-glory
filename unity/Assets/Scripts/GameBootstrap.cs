using System;
using UnityEngine;

namespace GridGlory
{
    public sealed class GameBootstrap : MonoBehaviour
    {
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        private static void Boot()
        {
            if (FindObjectOfType<GameBootstrap>() != null) return;
            var root = new GameObject("GridAndGlory");
            DontDestroyOnLoad(root);
            root.AddComponent<GameBootstrap>();
        }

        private void Awake()
        {
            Application.targetFrameRate = 60;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            var world = new GameObject("3D Stadium");
            world.transform.SetParent(transform, false);
            world.AddComponent<StadiumBuilder>();

            var ui = new GameObject("Game UI");
            ui.transform.SetParent(transform, false);
            ui.AddComponent<GameUI>();
        }
    }
}