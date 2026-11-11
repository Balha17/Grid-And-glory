using UnityEngine;

namespace GridGlory
{
    public sealed class StadiumBuilder : MonoBehaviour
    {
        private static Material Mat(Color c, float metallic = 0f)
        {
            var m = new Material(Shader.Find("Standard"));
            m.color = c;
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Glossiness", 0.28f);
            return m;
        }

        private void Awake()
        {
            Build();
        }

        private void Build()
        {
            var grassA = Mat(new Color(.055f,.34f,.15f));
            var grassB = Mat(new Color(.075f,.40f,.18f));
            var white = Mat(new Color(.92f,.95f,.91f));
            var dark = Mat(new Color(.025f,.045f,.075f));
            var blue = Mat(new Color(.04f,.28f,.92f));
            var red = Mat(new Color(.88f,.09f,.12f));
            var gold = Mat(new Color(1f,.66f,.12f), .25f);

            RenderSettings.ambientLight = new Color(.52f,.57f,.66f);
            var light = new GameObject("Stadium floodlights").AddComponent<Light>();
            light.type = LightType.Directional;
            light.intensity = 1.25f;
            light.transform.rotation = Quaternion.Euler(48f,-32f,0f);
            light.shadows = LightShadows.Soft;

            var cameraObject = new GameObject("Match Camera");
            var cam = cameraObject.AddComponent<Camera>();
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(.015f,.035f,.075f);
            cam.fieldOfView = 43f;
            cam.transform.position = new Vector3(0, 43, -36);
            cam.transform.LookAt(new Vector3(0,0,1));
            cam.nearClipPlane = .1f;
            cam.farClipPlane = 180f;
            cameraObject.tag = "MainCamera";

            Cube("Pitch base", new Vector3(0,-.18f,0), new Vector3(58,.3f,38), grassA);
            for (int i=0;i<10;i++)
                Cube("Grass stripe", new Vector3(-25.2f+i*5.6f,-.015f,0), new Vector3(2.8f,.025f,34), i%2==0?grassA:grassB);

            Line("Touchline north", new Vector3(0,.035f,17), new Vector3(52,.045f,.12f), white);
            Line("Touchline south", new Vector3(0,.035f,-17), new Vector3(52,.045f,.12f), white);
            Line("Goal line east", new Vector3(26,.035f,0), new Vector3(.12f,.045f,34), white);
            Line("Goal line west", new Vector3(-26,.035f,0), new Vector3(.12f,.045f,34), white);
            Line("Halfway", new Vector3(0,.04f,0), new Vector3(.12f,.05f,34), white);
            Circle("Center circle", Vector3.zero, 5.2f, white);
            Circle("Center spot", new Vector3(0,.05f,0), .22f, white);
            BoxOutline("Left penalty", new Vector3(-20,.04f,0), new Vector3(12,.05f,22), white);
            BoxOutline("Right penalty", new Vector3(20,.04f,0), new Vector3(12,.05f,22), white);
            BoxOutline("Left six yard", new Vector3(-24,.05f,0), new Vector3(4,.05f,10), white);
            BoxOutline("Right six yard", new Vector3(24,.05f,0), new Vector3(4,.05f,10), white);
            Goal(-1, white); Goal(1, white);

            // Stadium bowl, LED ribbon and seating tiers.
            for (int side=-1;side<=1;side+=2)
            {
                for(int tier=0;tier<5;tier++)
                {
                    var seat = Mat(Color.Lerp(new Color(.035f,.09f,.19f),new Color(.11f,.24f,.39f),tier/5f));
                    Cube("Stand tier", new Vector3(0,1.2f+tier*1.15f,side*(22+tier*.7f)), new Vector3(62,1.1f,5.5f), seat);
                }
            }
            for (int side=-1;side<=1;side+=2)
                for(int tier=0;tier<5;tier++)
                {
                    var seat = Mat(tier%2==0?new Color(.055f,.12f,.25f):new Color(.08f,.18f,.32f));
                    Cube("End stand tier", new Vector3(side*(33+tier*.7f),1.2f+tier*1.15f,0), new Vector3(5.5f,1.1f,42), seat);
                }
            Cube("LED ribbon north", new Vector3(0,1.1f,19.2f), new Vector3(55,.55f,.5f), gold);
            Cube("LED ribbon south", new Vector3(0,1.1f,-19.2f), new Vector3(55,.55f,.5f), gold);

            // Two readable 4-3-3 formations with distinct kits.
            Vector3[] home = {new(-23,0,0),new(-17,0,-12),new(-18,0,-4),new(-18,0,4),new(-17,0,12),new(-8,0,-10),new(-8,0,0),new(-8,0,10),new(2,0,-11),new(5,0,0),new(2,0,11)};
            Vector3[] away = {new(23,0,0),new(17,0,-12),new(18,0,-4),new(18,0,4),new(17,0,12),new(8,0,-10),new(8,0,0),new(8,0,10),new(-2,0,-11),new(-5,0,0),new(-2,0,11)};
            for(int i=0;i<11;i++)
            {
                Player("Blue player "+(i+1),home[i],blue,gold);
                Player("Red player "+(i+1),away[i],red,white);
            }
            var ball = GameObject.CreatePrimitive(PrimitiveType.Sphere);
            ball.name="Match ball"; ball.transform.position=new Vector3(0,.48f,0);
            ball.transform.localScale=Vector3.one*.72f;
            ball.GetComponent<Renderer>().material=Mat(Color.white);
            var floor = Cube("Stadium floor",new Vector3(0,-.55f,0),new Vector3(100,.3f,100),dark);
        }

        private void Player(string n, Vector3 p, Material kit, Material trim)
        {
            var root = new GameObject(n); root.transform.position=p+new Vector3(0,.1f,0);
            var body=GameObject.CreatePrimitive(PrimitiveType.Capsule);
            body.name="Kit"; body.transform.SetParent(root.transform,false);
            body.transform.localPosition=new Vector3(0,.95f,0);
            body.transform.localScale=new Vector3(.68f,.92f,.48f);
            body.GetComponent<Renderer>().material=kit;
            var head=GameObject.CreatePrimitive(PrimitiveType.Sphere);
            head.name="Head"; head.transform.SetParent(root.transform,false);
            head.transform.localPosition=new Vector3(0,2.05f,0);
            head.transform.localScale=Vector3.one*.48f;
            head.GetComponent<Renderer>().material=trim;
        }

        private void Goal(int side, Material white)
        {
            float x=side*26.5f;
            Cube("Goal crossbar",new Vector3(x,2.6f,0),new Vector3(.2f,.18f,7.4f),white);
            Cube("Goal post A",new Vector3(x,1.3f,-3.6f),new Vector3(.18f,2.6f,.18f),white);
            Cube("Goal post B",new Vector3(x,1.3f,3.6f),new Vector3(.18f,2.6f,.18f),white);
        }
        private void Circle(string n,Vector3 c,float r,Material m)
        {
            var o=new GameObject(n); o.transform.position=c+Vector3.up*.045f;
            var lr=o.AddComponent<LineRenderer>(); lr.useWorldSpace=false; lr.loop=true; lr.positionCount=96;
            lr.startWidth=.09f; lr.endWidth=.09f; lr.material=m;
            for(int i=0;i<96;i++){float a=i*Mathf.PI*2/96;lr.SetPosition(i,new Vector3(Mathf.Cos(a)*r,0,Mathf.Sin(a)*r));}
        }
        private void BoxOutline(string n,Vector3 c,Vector3 size,Material m)
        {
            Line(n+" top",c+new Vector3(0,0,size.z/2),new Vector3(size.x,.05f,.08f),m);
            Line(n+" bottom",c-new Vector3(0,0,size.z/2),new Vector3(size.x,.05f,.08f),m);
            Line(n+" left",c-new Vector3(size.x/2,0,0),new Vector3(.08f,.05f,size.z),m);
            Line(n+" right",c+new Vector3(size.x/2,0,0),new Vector3(.08f,.05f,size.z),m);
        }
        private void Line(string n,Vector3 p,Vector3 s,Material m)=>Cube(n,p,s,m);
        private void Cube(string n,Vector3 p,Vector3 s,Material m)
        {
            var o=GameObject.CreatePrimitive(PrimitiveType.Cube);o.name=n;o.transform.position=p;o.transform.localScale=s;o.GetComponent<Renderer>().material=m;
            var col=o.GetComponent<Collider>();if(col)Destroy(col);
        }
    }
}