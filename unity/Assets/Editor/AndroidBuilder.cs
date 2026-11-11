using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace GridGlory.Editor
{
    public static class AndroidBuilder
    {
        public static void BuildAndroid()
        {
            const string output = "Build/GridAndGlory.apk";
            Directory.CreateDirectory("Build");
            Directory.CreateDirectory("Assets/Scenes");
            EditorUserBuildSettings.buildAppBundle = false;
            EditorUserBuildSettings.androidBuildType = AndroidBuildType.Debug;
            PlayerSettings.productName = "Grid & Glory";
            PlayerSettings.companyName = "Grid Glory Studio";
            PlayerSettings.applicationIdentifier = "com.gridglory.footballquiz";
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.Portrait;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel23;
            PlayerSettings.Android.forceInternetPermission = true;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, "Assets/Scenes/Main.unity");
            var report = BuildPipeline.BuildPlayer(new BuildPlayerOptions
            {
                scenes = new[] { "Assets/Scenes/Main.unity" },
                locationPathName = output,
                target = BuildTarget.Android,
                options = BuildOptions.Development
            });
            if (report.summary.result != BuildResult.Succeeded)
                throw new System.Exception("Android build failed: " + report.summary.result);
            Debug.Log("APK created: " + Path.GetFullPath(output));
        }
    }
}