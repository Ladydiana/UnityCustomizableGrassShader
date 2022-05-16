Shader "Roystan/Grass"
{
    Properties
    {
		[Header(Shading)]
        _TopColor("Top Color", Color) = (1,1,1,1)
		_BottomColor("Bottom Color", Color) = (1,1,1,1)
		_TranslucentGain("Translucent Gain", Range(0,1)) = 0.5
    }

	CGINCLUDE
	#include "UnityCG.cginc"
	#include "Autolight.cginc"

	// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
	// Extended discussion on this function can be found at the following link:
	// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
	// Returns a number in the 0...1 range.
	float rand(float3 co)
	{
		return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
	}

	// Construct a rotation matrix that rotates around the provided axis, sourced from:
	// https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
	float3x3 AngleAxis3x3(float angle, float3 axis)
	{
		float c, s;
		sincos(angle, s, c);

		float t = 1 - c;
		float x = axis.x;
		float y = axis.y;
		float z = axis.z;

		return float3x3(
			t * x * x + c, t * x * y - s * z, t * x * z + s * y,
			t * x * y + s * z, t * y * y + c, t * y * z - s * x,
			t * x * z - s * y, t * y * z + s * x, t * z * z + c
			);
	}

	struct vertexInput
	{
		float4 vertex : POSITION;
		float3 normal : NORMAL;
		float4 tangent : TANGENT;
	};

	struct vertexOutput
	{
		float4 vertex : SV_POSITION;
		float3 normal : NORMAL;
		float4 tangent : TANGENT;
	};


	float4 vert(float4 vertex : POSITION) : SV_POSITION
	{
		//return UnityObjectToClipPos(vertex);
		return vertex;
	}

	vertexOutput vert(vertexInput v)
	{
		vertexOutput o;
		o.vertex = v.vertex;
		o.normal = v.normal;
		o.tangent = v.tangent;
		return o;
	}

	struct geometryOutput
	{
		float4 pos : SV_POSITION;
	};

	geometryOutput VertexOutput(float3 pos)
	{
		geometryOutput o;
		o.pos = UnityObjectToClipPos(pos);
		return o;
	}

	/*	Declare a geometry shader named geo.
		Parameters: - triangle float4 IN[3] : SV_POSITION; input a triangle defined by 3 points
					- TriangleStream<geometryOutput> triStream; output a stream of triangles with the geometryOutput structure
					- [maxvertexcount(3)]; we will emit a max of 3 vertices
		
	*/ 
	[maxvertexcount(3)]
	//void geo(triangle float4 IN[3] : SV_POSITION, inout TriangleStream<geometryOutput> triStream)
	void geo(triangle vertexOutput IN[3], inout TriangleStream<geometryOutput> triStream)
	{

		// Creating a tringle as output to vizualize the geometry shader
		// Problem 1: the triangle is being rendered in screen space
		// Fix 1: Added UnityObjectToClipPos
		// Problem 2: The positions we are assigning to the triangle's vertices are constant—they do not change for each input vertex— placing all the triangles atop one another.
		// Fix 2: Added the pos offset for each triangle
		//float3 pos = IN[0];
		float3 pos = IN[0].vertex;
		float3 vNormal = IN[0].normal;
		float4 vTangent = IN[0].tangent;
		float3 vBinormal = cross(vNormal, vTangent) * vTangent.w;


		// matrix to transform between tangent and local space
		float3x3 tangentToLocal = float3x3(
			vTangent.x, vBinormal.x, vNormal.x,
			vTangent.y, vBinormal.y, vNormal.y,
			vTangent.z, vBinormal.z, vNormal.z
			);

		
		/*geometryOutput o;

		//o.pos = float4(0.5, 0, 0, 1);
		//o.pos = UnityObjectToClipPos(float4(0.5, 0, 0, 1));
		o.pos = UnityObjectToClipPos(pos + float3(0.5, 0, 0));
		triStream.Append(o);

		//o.pos = float4(-0.5, 0, 0, 1);
		//o.pos = UnityObjectToClipPos(float4(-0.5, 0, 0, 1));
		o.pos = UnityObjectToClipPos(pos + float3(-0.5, 0, 0));
		triStream.Append(o);

		//o.pos = float4(0, 1, 0, 1);
		//o.pos = UnityObjectToClipPos(float4(0, 1, 0, 1));
		o.pos = UnityObjectToClipPos(pos + float3(0, 1, 0));
		triStream.Append(o); */


		triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(0.5, 0, 0))));
		triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(-0.5, 0, 0))));
		triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(0, 0, 1))));
		//triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(0, 1, 0))));
	}

	ENDCG

    SubShader
    {
		Cull Off

        Pass
        {
			Tags
			{
				"RenderType" = "Opaque"
				"LightMode" = "ForwardBase"
			}

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
			#pragma geometry geo // make sure the SubShader uses the geometry shader
			#pragma target 4.6
            
			#include "Lighting.cginc"

			float4 _TopColor;
			float4 _BottomColor;
			float _TranslucentGain;

			float4 frag (float4 vertex : SV_POSITION, fixed facing : VFACE) : SV_Target
            {	
				return float4(1, 1, 1, 1);
            }
            ENDCG
        }
    }
}