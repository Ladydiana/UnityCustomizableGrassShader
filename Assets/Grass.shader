Shader "Roystan/Grass"
{
    Properties
    {
		[Header(Shading)]
        _TopColor("Top Color", Color) = (1,1,1,1)
		_BottomColor("Bottom Color", Color) = (1,1,1,1)
		_TranslucentGain("Translucent Gain", Range(0,1)) = 0.5
		_BladeWidth("Blade Width", Float) = 0.05
		_BladeWidthRandom("Blade Width Random", Float) = 0.02
		_BladeHeight("Blade Height", Float) = 0.5
		_BladeHeightRandom("Blade Height Random", Float) = 0.3
		_BendRotationRandom("Bend Rotation Random", Range(0, 1)) = 0.2
		_TessellationUniform("Tessellation Uniform", Range(1, 64)) = 1
		_WindDistortionMap("Wind Distortion Map", 2D) = "white" {}
		_WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
		_WindStrength("Wind Strength", Float) = 1
    }

	CGINCLUDE
	#include "UnityCG.cginc"
	#include "Autolight.cginc"
	#include "Shaders/CustomTessellation.cginc" // for the 
	#define BLADE_SEGMENTS 3

	

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

	/* Removed because they are defined in the CustomTessellation.cginc
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
	}*/

	struct geometryOutput
	{
		float4 pos : SV_POSITION;
		// UV for the colors
		float2 uv : TEXCOORD0;
		unityShadowCoord4 _ShadowCoord : TEXCOORD1; //for the shadow collecting
	};

	// added UV for colors
	geometryOutput VertexOutput(float3 pos, float2 uv)
	{
		geometryOutput o;
		o.pos = UnityObjectToClipPos(pos);
		o.uv = uv;
		o._ShadowCoord = ComputeScreenPos(o.pos); //etrieve a float value representing whether the surface is in shadows or not
		#if UNITY_PASS_SHADOWCASTER
		// Applying the bias prevents artifacts from appearing on the surface.
				o.pos = UnityApplyLinearShadowBias(o.pos);
		#endif
		return o;
	}


	float _BladeHeight;
	float _BladeHeightRandom;
	float _BladeWidth;
	float _BladeWidthRandom;
	float _BendRotationRandom;
	sampler2D _WindDistortionMap;
	float4 _WindDistortionMap_ST;
	float2 _WindFrequency;
	float _WindStrength;

	//Re-usable function to generate a grass vertex
	geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float2 uv, float3x3 transformMatrix)
	{
		float3 tangentPoint = float3(width, 0, height);

		float3 localPosition = vertexPosition + mul(transformMatrix, tangentPoint);
		return VertexOutput(localPosition, uv);
	}

	/*	Declare a geometry shader named geo.
		Parameters: - triangle float4 IN[3] : SV_POSITION; input a triangle defined by 3 points
					- TriangleStream<geometryOutput> triStream; output a stream of triangles with the geometryOutput structure
					- [maxvertexcount(3)]; we will emit a max of 3 vertices
		
	*/ 
	//[maxvertexcount(3)]
	[maxvertexcount(BLADE_SEGMENTS * 2 + 1)]
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

		
		float3x3 bendRotationMatrix = AngleAxis3x3(rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1, 0, 0));


		// matrix to transform between tangent and local space
		float3x3 tangentToLocal = float3x3(
			vTangent.x, vBinormal.x, vNormal.x,
			vTangent.y, vBinormal.y, vNormal.y,
			vTangent.z, vBinormal.z, vNormal.z
			);

		// For the random rotation
		// use the input position pos as the random seed for our rotation. This way, every blade will get a different rotation, but it will be consistent between frames.
		float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos) * UNITY_TWO_PI, float3(0, 0, 1));
		// With different direction
		//float3x3 transformationMatrix = mul(tangentToLocal, facingRotationMatrix);
		//uv for the wind
		float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
		float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
		float3 wind = normalize(float3(windSample.x, windSample.y, 0));
		float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);
		//With direction and bend
		//float3x3 transformationMatrix = mul(mul(tangentToLocal, facingRotationMatrix), bendRotationMatrix);
		//With wind
		float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix), bendRotationMatrix);

		
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

		//Width and Height of a blade
		float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
		float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;

		//Base of the blade needs to stay attached to its surface during wind
		float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);

		//Blade segments
		for (int i = 0; i < BLADE_SEGMENTS; i++)
		{
			float t = i / (float)BLADE_SEGMENTS;
			float segmentHeight = height * t;
			float segmentWidth = width * (1 - t);

			float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

			triStream.Append(GenerateGrassVertex(pos, segmentWidth, segmentHeight, float2(0, t), transformMatrix));
			triStream.Append(GenerateGrassVertex(pos, -segmentWidth, segmentHeight, float2(1, t), transformMatrix));
		}

		triStream.Append(GenerateGrassVertex(pos, 0, height, float2(0.5, 1), transformationMatrix));

		/*triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(0.5, 0, 0)), float2(0, 0)));
		triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(-0.5, 0, 0)), float2(1, 0)));
		triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(0, 0, 1)), float2(0.5, 1)));*/
		//triStream.Append(VertexOutput(pos + mul(tangentToLocal, float3(0, 1, 0))));
		//Random rotation
		/*triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(0.5, 0, 0)), float2(0, 0)));
		triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(-0.5, 0, 0)), float2(1, 0)));
		triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(0, 0, 1)), float2(0.5, 1)));*/

		//Width and Height
		/*triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(width, 0, 0)), float2(0, 0)));
		triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(-width, 0, 0)), float2(1, 0)));
		triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(0, 0, height)), float2(0.5, 1)));*/

		
		/*triStream.Append(VertexOutput(pos + mul(transformationMatrixFacing, float3(width, 0, 0)), float2(0, 0)));
		triStream.Append(VertexOutput(pos + mul(transformationMatrixFacing, float3(-width, 0, 0)), float2(1, 0)));
		triStream.Append(VertexOutput(pos + mul(transformationMatrix, float3(0, 0, height)), float2(0.5, 1)));*/

		// Outputting via the generate function.
		/*triStream.Append(GenerateGrassVertex(pos, width, 0, float2(0, 0), transformationMatrixFacing));
		triStream.Append(GenerateGrassVertex(pos, -width, 0, float2(1, 0), transformationMatrixFacing));
		triStream.Append(GenerateGrassVertex(pos, 0, height, float2(0.5, 1), transformationMatrix));*/
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
			#pragma hull hull
			#pragma domain domain
			#pragma multi_compile_fwdbase
            
			#include "Lighting.cginc"

			float4 _TopColor;
			float4 _BottomColor;
			float _TranslucentGain;

			//float4 frag (float4 vertex : SV_POSITION, fixed facing : VFACE) : SV_Target
			float4 frag(geometryOutput i, fixed facing : VFACE) : SV_Target // Added UV
            {	
				//return float4(1, 1, 1, 1);
				//return lerp(_BottomColor, _TopColor, i.uv.y); //interpolating between top and bottom uv
				return SHADOW_ATTENUATION(i); //for the shadow
            }
            ENDCG
        }

		Pass
		{
			Tags
			{
				"LightMode" = "ShadowCaster"
			}

			CGPROGRAM
			#pragma vertex vert
			#pragma geometry geo
			#pragma fragment frag
			#pragma hull hull
			#pragma domain domain
			#pragma target 4.6
			#pragma multi_compile_shadowcaster

			float4 frag(geometryOutput i) : SV_Target
			{
				SHADOW_CASTER_FRAGMENT(i)
			}

			ENDCG
		}
    }
}