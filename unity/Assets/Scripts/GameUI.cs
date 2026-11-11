using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;
using NativeWebSocket;
using Newtonsoft.Json.Linq;
using UnityEngine;
using UnityEngine.UI;

namespace GridGlory
{
    public sealed class GameUI : MonoBehaviour
    {
        private const string ServerUrl = "wss://grid-and-glory.onrender.com/ws";
        private WebSocket socket;
        private Canvas canvas;
        private Font font;
        private GameObject homeScreen, matchScreen, waitCard, resultCard;
        private Text title, subtitle, waitText, question, status, score, timer;
        private Transform optionsRoot;
        private Button onlineButton, aiButton, cancelButton;
        private string playerId="", sessionToken="", token="", selectedId="", joinMode="ai";
        private string phase="home";
        private int seq, myGoals, rivalGoals;
        private bool answered;
        private float deadline;
        private readonly Dictionary<string,Button> optionButtons=new Dictionary<string,Button>();

        private void Start()
        {
            font=Resources.GetBuiltinResource<Font>("Arial.ttf");
            BuildCanvas();
            ShowHome();
        }
        private void Update()
        {
#if !UNITY_WEBGL || UNITY_EDITOR
            socket?.DispatchMessageQueue();
#endif
            if(deadline>0 && phase=="connecting")
                waitText.text="CONNECTING TO SERVER…\n"+Mathf.CeilToInt(Mathf.Max(0,deadline-Time.realtimeSinceStartup))+"s";
            if(deadline>0 && (phase=="question_open" || phase=="shooting_chance"))
                timer.text=Mathf.CeilToInt(Mathf.Max(0,deadline-Time.realtimeSinceStartup)).ToString();
        }
        private void BuildCanvas()
        {
            var go=new GameObject("Canvas",typeof(Canvas),typeof(CanvasScaler),typeof(GraphicRaycaster));
            canvas=go.GetComponent<Canvas>();canvas.renderMode=RenderMode.ScreenSpaceOverlay;
            var scaler=go.GetComponent<CanvasScaler>();scaler.uiScaleMode=CanvasScaler.ScaleMode.ScaleWithScreenSize;scaler.referenceResolution=new Vector2(720,1280);scaler.matchWidthOrHeight=.5f;
            var es=new GameObject("EventSystem",typeof(UnityEngine.EventSystems.EventSystem),typeof(UnityEngine.EventSystems.StandaloneInputModule));
            var bg=Panel(go.transform,"Backdrop",new Vector2(0,0),new Vector2(1,1),new Color(.015f,.035f,.075f,.94f));
            homeScreen=Panel(bg.transform,"Home",Vector2.zero,Vector2.one,new Color(.015f,.035f,.075f,.97f));
            var badge=Label(homeScreen.transform,"GRID  &  GLORY",52,new Vector2(.05f,.72f),new Vector2(.95f,.86f),new Color(1f,.75f,.25f),TextAnchor.MiddleCenter);
            badge.fontStyle=FontStyle.Bold;
            Label(homeScreen.transform,"THE ULTIMATE FOOTBALL QUIZ BATTLE",19,new Vector2(.05f,.66f),new Vector2(.95f,.72f),new Color(.65f,.8f,1f),TextAnchor.MiddleCenter);
            Label(homeScreen.transform,"⚽   1v1 FOOTBALL TRIVIA   •   RISE TO LEGEND",17,new Vector2(.06f,.57f),new Vector2(.94f,.63f),Color.white,TextAnchor.MiddleCenter);
            onlineButton=MakeButton(homeScreen.transform,"PLAY ONLINE",new Vector2(.12f,.40f),new Vector2(.88f,.50f),new Color(.88f,.48f,.08f));
            onlineButton.onClick.AddListener(()=>StartConnection("online"));
            aiButton=MakeButton(homeScreen.transform,"PLAY VS AI",new Vector2(.12f,.29f),new Vector2(.88f,.39f),new Color(.04f,.28f,.72f));
            aiButton.onClick.AddListener(()=>StartConnection("ai"));
            Label(homeScreen.transform,"ONLINE DUELS  •  SMART AI  •  FOOTBALL KNOWLEDGE",14,new Vector2(.04f,.08f),new Vector2(.96f,.14f),new Color(.4f,.6f,.8f),TextAnchor.MiddleCenter);

            waitCard=Panel(homeScreen.transform,"Matchmaking card",new Vector2(.08f,.36f),new Vector2(.92f,.62f),new Color(.025f,.07f,.14f,.99f));
            waitText=Label(waitCard.transform,"CONNECTING TO SERVER…",23,new Vector2(.05f,.38f),new Vector2(.95f,.88f),new Color(1f,.83f,.42f),TextAnchor.MiddleCenter);
            cancelButton=MakeButton(waitCard.transform,"CANCEL",new Vector2(.16f,.08f),new Vector2(.84f,.32f),new Color(.45f,.08f,.1f));
            cancelButton.onClick.AddListener(CancelMatchmaking);

            matchScreen=Panel(bg.transform,"Match HUD",Vector2.zero,Vector2.one,Color.clear);
            var top=Panel(matchScreen.transform,"Score bar",new Vector2(.04f,.86f),new Vector2(.96f,.98f),new Color(.015f,.035f,.075f,.92f));
            score=Label(top.transform,"YOU  0  —  0  RIVAL",25,Vector2.zero,Vector2.one,Color.white,TextAnchor.MiddleCenter);
            var bottom=Panel(matchScreen.transform,"Question dock",new Vector2(.035f,.025f),new Vector2(.965f,.39f),new Color(.012f,.027f,.065f,.98f));
            timer=Label(bottom.transform,"",22,new Vector2(.82f,.83f),new Vector2(.97f,.98f),new Color(1f,.75f,.25f),TextAnchor.MiddleCenter);
            question=Label(bottom.transform,"Get ready!",22,new Vector2(.04f,.60f),new Vector2(.94f,.92f),Color.white,TextAnchor.MiddleCenter);
            status=Label(bottom.transform,"",16,new Vector2(.04f,.49f),new Vector2(.94f,.60f),new Color(.65f,.8f,1f),TextAnchor.MiddleCenter);
            var scroll=Panel(bottom.transform,"Options",new Vector2(.04f,.04f),new Vector2(.96f,.48f),Color.clear);
            var layout=scroll.AddComponent<VerticalLayoutGroup>();layout.spacing=8;layout.childControlHeight=true;layout.childControlWidth=true;layout.childForceExpandHeight=true;layout.childForceExpandWidth=true;
            optionsRoot=scroll.transform;
            resultCard=Panel(matchScreen.transform,"Full time",new Vector2(.08f,.30f),new Vector2(.92f,.70f),new Color(.015f,.04f,.09f,.99f));
            Label(resultCard.transform,"FULL TIME",32,new Vector2(.05f,.60f),new Vector2(.95f,.9f),new Color(1f,.76f,.25f),TextAnchor.MiddleCenter);
            var again=MakeButton(resultCard.transform,"PLAY AGAIN • VS AI",new Vector2(.1f,.30f),new Vector2(.9f,.48f),new Color(.04f,.3f,.72f));
            again.onClick.AddListener(()=>StartConnection("ai"));
            var menu=MakeButton(resultCard.transform,"MAIN MENU",new Vector2(.1f,.08f),new Vector2(.9f,.26f),new Color(.15f,.2f,.3f));
            menu.onClick.AddListener(ShowHome);
            matchScreen.SetActive(false);waitCard.SetActive(false);resultCard.SetActive(false);
        }
        private GameObject Panel(Transform parent,string name,Vector2 min,Vector2 max,Color color)
        {
            var go=new GameObject(name,typeof(RectTransform),typeof(Image));go.transform.SetParent(parent,false);
            var rt=go.GetComponent<RectTransform>();rt.anchorMin=min;rt.anchorMax=max;rt.offsetMin=Vector2.zero;rt.offsetMax=Vector2.zero;
            go.GetComponent<Image>().color=color;return go;
        }
        private Text Label(Transform parent,string value,int size,Vector2 min,Vector2 max,Color color,TextAnchor align)
        {
            var go=new GameObject("Text",typeof(RectTransform),typeof(Text));go.transform.SetParent(parent,false);
            var rt=go.GetComponent<RectTransform>();rt.anchorMin=min;rt.anchorMax=max;rt.offsetMin=new Vector2(8,4);rt.offsetMax=new Vector2(-8,-4);
            var t=go.GetComponent<Text>();t.font=font;t.text=value;t.fontSize=size;t.color=color;t.alignment=align;t.horizontalOverflow=HorizontalWrapMode.Wrap;t.verticalOverflow=VerticalWrapMode.Truncate;return t;
        }
        private Button MakeButton(Transform parent,string text,Vector2 min,Vector2 max,Color color)
        {
            var go=Panel(parent,text,min,max,color);var b=go.AddComponent<Button>();
            var colors=b.colors;colors.normalColor=color;colors.highlightedColor=Color.Lerp(color,Color.white,.16f);colors.pressedColor=Color.Lerp(color,Color.black,.2f);b.colors=colors;
            var label=Label(go.transform,text,21,Vector2.zero,Vector2.one,Color.white,TextAnchor.MiddleCenter);label.fontStyle=FontStyle.Bold;
            return b;
        }
        private void ShowHome()
        {
            phase="home";deadline=0;homeScreen.SetActive(true);matchScreen.SetActive(false);waitCard.SetActive(false);resultCard.SetActive(false);
            onlineButton.interactable=true;aiButton.interactable=true;
        }
        private async void StartConnection(string mode)
        {
            joinMode=mode;phase="connecting";playerId="";sessionToken="";deadline=Time.realtimeSinceStartup+20f;
            homeScreen.SetActive(true);matchScreen.SetActive(false);waitCard.SetActive(true);resultCard.SetActive(false);
            onlineButton.interactable=false;aiButton.interactable=false;
            waitText.text=mode=="ai"?"CONNECTING…\nCREATING AN AI MATCH":"CONNECTING…\nSEARCHING FOR A PLAYER";
            try
            {
                if(socket!=null){socket.OnOpen-=OnSocketOpen;socket.OnMessage-=OnSocketMessage;socket.OnError-=OnSocketError;socket.OnClose-=OnSocketClose;await socket.Close();}
                socket=new WebSocket(ServerUrl);
                socket.OnOpen+=OnSocketOpen;
                socket.OnMessage+=OnSocketMessage;
                socket.OnError+=OnSocketError;
                socket.OnClose+=OnSocketClose;
                await socket.Connect();
            }
            catch(Exception e){Fail("CONNECTION FAILED: "+e.Message);}
        }
        private void OnSocketOpen()
        {
            // The server sends "welcome" first; hello is sent only in that handler.
        }
        private void OnSocketMessage(byte[] bytes)
        {
            var raw=Encoding.UTF8.GetString(bytes);
            try{HandleFrame(JObject.Parse(raw));}catch(Exception e){Debug.LogWarning("Bad server frame: "+e.Message);}
        }
        private void OnSocketError(string error)=>Debug.LogWarning("Grid & Glory socket: "+error);
        private void OnSocketClose(WebSocketCloseCode code)
        {
            if(phase=="connecting")Fail("SERVER CONNECTION CLOSED");
        }
        private async void Send(string type,JObject payload)
        {
            if(socket==null||socket.State!=WebSocketState.Open)return;
            seq++;
            var frame=new JObject{{"v",1},{"type",type},{"seq",seq},{"ts",DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()},{"payload",payload}};
            await socket.SendText(frame.ToString(Newtonsoft.Json.Formatting.None));
        }
        private void HandleFrame(JObject frame)
        {
            string type=(string)frame["type"]??"";
            JObject p=frame["payload"] as JObject??new JObject();
            switch(type)
            {
                case "welcome": Send("hello",new JObject{{"deviceId",SystemInfo.deviceUniqueIdentifier},{"locale","en"},{"region","MENA"},{"displayName","Striker"}}); break;
                case "hello.ack":
                    playerId=(string)p["playerId"]??"";sessionToken=(string)p["sessionToken"]??"";
                    Send(joinMode=="ai"?"bot.join":"queue.join",new JObject());waitText.text=joinMode=="ai"?"CREATING YOUR AI MATCH…":"SEARCHING FOR AN OPPONENT…";break;
                case "queue.joined": waitText.text="SEARCHING FOR A PLAYER…\nAI BACKUP IN 15 SECONDS";break;
                case "match.found": waitCard.SetActive(false);waitText.text="OPPONENT FOUND";break;
                case "match.start": case "match.second_half":
                    deadline=0;phase="round_intro";matchScreen.SetActive(true);homeScreen.SetActive(false);UpdateScore(p);status.text="KICK OFF";break;
                case "round.intro": phase="round_intro";question.text="ROUND "+(string)p["roundNo"]+" • GET READY";break;
                case "round.question": case "shoot.question":
                    phase=type=="shoot.question"?"shooting_chance":"question_open";token=(string)p["token"]??"";answered=false;selectedId="";
                    RenderQuestion(p["view"] as JObject,p);break;
                case "round.answer_ack": status.text="ANSWER LOCKED";break;
                case "round.opponent_answered": status.text="RIVAL HAS ANSWERED";break;
                case "round.reveal": case "shoot.reveal":
                    phase="round_reveal";deadline=0;UpdateScore(p);
                    string outcome=(string)p["outcome"]??"";
                    ShowFeedback((string)p["correctOptionText"]??"",outcome=="correct"||((bool?)p["scored"]??false));break;
                case "match.half": phase="half_time";UpdateScore(p);status.text="HALF TIME";question.text="SECOND HALF";break;
                case "match.end":
                    phase="ended";deadline=0;UpdateScore(p);resultCard.SetActive(true);status.text=((string)p["outcome"]??"").ToUpperInvariant();break;
                case "error": Fail("SERVER ERROR • "+(string)p["code"]);break;
            }
        }
        private void RenderQuestion(JObject view,JObject envelope)
        {
            if(view==null){question.text="QUESTION UNAVAILABLE";return;}
            question.text=(string)view["prompt"]??"";
            JObject data=view["formatData"] as JObject;
            if(data!=null)
            {
                string format=(string)data["type"]??"";
                if(format=="career_path")
                {
                    var names=new List<string>();var clubs=data["clubs"] as JArray;
                    if(clubs!=null)foreach(var c in clubs)names.Add((string)c["name"]??"");
                    question.text=string.Join("  ›  ",names)+"\n"+question.text;
                }
                else if(format=="emoji_story")question.text=(string)data["emoji"]+"\n"+question.text;
                else if(format=="stat_highlow")question.text=(string)data["statLabel"]+"\n"+question.text;
            }
            ClearOptions();
            var opts=view["options"] as JArray;if(opts==null||opts.Count<2){question.text="QUESTION DATA MISSING";return;}
            foreach(JObject opt in opts)
            {
                string id=(string)opt["id"]??"",label=(string)opt["text"]??"";
                var b=MakeButton(optionsRoot,label,new Vector2(0,0),new Vector2(1,1),new Color(.055f,.13f,.24f));
                b.GetComponent<RectTransform>().sizeDelta=new Vector2(0,74);
                b.onClick.AddListener(()=>SubmitAnswer(id));optionButtons[id]=b;
            }
            JObject p=envelope["payload"] as JObject;
            long serverNow=(long?)p["serverNow"]??DateTimeOffset.UtcNow.ToUnixTimeMilliseconds();
            long endAt=(long?)p["windowEndsAt"]??serverNow+9000;
            deadline=Time.realtimeSinceStartup+Mathf.Max(0,(endAt-serverNow)/1000f);
            status.text=phase=="shooting_chance"?"SHOOTING CHANCE":"ANSWER FAST TO WIN THE BALL";
        }
        private void SubmitAnswer(string id)
        {
            if(answered||string.IsNullOrEmpty(token))return;answered=true;selectedId=id;
            Send("round.answer",new JObject{{"token",token},{"optionId",id},{"clientMs",DateTimeOffset.UtcNow.ToUnixTimeMilliseconds()}});
            foreach(var b in optionButtons.Values)b.interactable=false;
            status.text="ANSWER SENT • WAITING";
        }
        private void ShowFeedback(string correctText,bool correct)
        {
            foreach(var pair in optionButtons)
            {
                var label=pair.Value.GetComponentInChildren<Text>();
                bool right=label!=null&&label.text==correctText;
                var image=pair.Value.GetComponent<Image>();
                if(right)image.color=new Color(.03f,.48f,.2f);
                else if(pair.Key==selectedId)image.color=new Color(.62f,.055f,.08f);
                pair.Value.interactable=false;
            }
            status.text=correct?"CORRECT":"WRONG";
            if(!string.IsNullOrEmpty(correctText))question.text=correctText;
        }
        private void UpdateScore(JObject p)
        {
            var goals=p["goals"] as JObject;
            if(goals!=null)
            {
                myGoals=(int?)goals[playerId]??myGoals;
                foreach(var prop in goals.Properties())if(prop.Name!=playerId)rivalGoals=(int)prop.Value;
            }
            score.text="YOU  "+myGoals+"  —  "+rivalGoals+"  RIVAL";
        }
        private void ClearOptions()
        {
            foreach(Transform child in optionsRoot)Destroy(child.gameObject);
            optionButtons.Clear();
        }
        private async void CancelMatchmaking()
        {
            if(socket!=null)
            {
                if(socket.State==WebSocketState.Open)Send("queue.leave",new JObject());
                await socket.Close();socket=null;
            }
            ShowHome();
        }
        private void Fail(string message)
        {
            deadline=0;phase="home";waitCard.SetActive(false);onlineButton.interactable=true;aiButton.interactable=true;
            waitText.text=message;Debug.LogWarning(message);
        }
        private void OnDestroy(){if(socket!=null)socket.Close();}
    }
}