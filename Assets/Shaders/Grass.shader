Shader "AmazingGrassShader"
{
    Properties
    {
		[Header(Shading)]
		[Toggle(FILL_WITH_RED)]
		_DryGrassEnabled("Enable Dry Grass", Float) = 1
        _TopColor("Top Color", Color) = (1,1,1,1)
		_BottomColor("Bottom Color", Color) = (1,1,1,1)
		_DryTopColor("Dry Top Color", Color) = (1,1,1,1)
		_DryBottomColor("Dry Bottom Color", Color) = (1,1,1,1)
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
		_BladeForward("Blade Forward Amount", Float) = 0.38
		_BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2
		_GrassLoadMap("Grass Load Map", 2D) = "white" {}
		_GrassThreshold("Grass Visibility Threshold", Range(-0.1, 1)) = 0.5
		_GrassTexture("Grass Texture", 2D) = "white" {}
		[Header(Collision)]
		_Collision("Collision", Vector) = (0, 0, 0, 0)
		_CollisionStrength("Collision Strength", Range(0, 1)) = 0.2
    }

	CGINCLUDE
	#include "UnityCG.cginc"
	#include "Autolight.cginc"
	#include "CustomTessellation.cginc" // for the tessellation
	#define BLADE_SEGMENTS 3

	

	
	// Returns a number in the [0, 1] range.
	float rand(float3 co)
	{
		return frac(sin( dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
	}

	//REALLY random. Use with care. Regenerates every render
	float reallyRandom(float3 co) {
		return frac(sin(_Time[0] * dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
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

	

	struct geometryOutput
	{
		float4 pos : SV_POSITION;
		// UV for the colors
		float2 uv : TEXCOORD0;
		unityShadowCoord4 _ShadowCoord : TEXCOORD1; //for the shadow collecting
		float3 normal : NORMAL; // for the light
	};

	// added UV for colors
	geometryOutput VertexOutput(float3 pos, float2 uv, float3 normal)

	{
		geometryOutput o;
		o.pos = UnityObjectToClipPos(pos);
		o.uv = uv;
		o._ShadowCoord = ComputeScreenPos(o.pos); //retrieve a float value representing whether the surface is in shadows or not
		o.normal = UnityObjectToWorldNormal(normal); // for the light
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
	float _BladeForward;
	float _BladeCurve;
	sampler2D _GrassLoadMap;
	float4 _GrassLoadMap_ST;
	float  _GrassThreshold;
	float4 _Collision;
	float _CollisionStrength;

	//Re-usable function to generate a grass vertex
	geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float2 uv, float3x3 transformMatrix)
	{
		float3 tangentPoint = float3(width, forward, height);

		// For the light
		float3 tangentNormal = normalize(float3(0, -1, forward));
		float3 localNormal = mul(transformMatrix, tangentNormal);

		float3 localPosition = vertexPosition + mul(transformMatrix, tangentPoint);
		//return VertexOutput(localPosition, uv);
		return VertexOutput(localPosition, uv, localNormal);

	}

	float4 GetCollisionVector(float3 pos, float3 realPointOfIntersection)
	{
		float3 collisionDiff = pos - realPointOfIntersection;
		float closeness = (1.0 - saturate(length(collisionDiff) / _Collision.w));
		return float4(
			float3(normalize(collisionDiff).x,
				0,
				normalize(collisionDiff).z) * closeness,
			0);
	}

	/*	geometry shader 
	*/ 
	
	[maxvertexcount(BLADE_SEGMENTS * 2 + 1)] 
	
	void geo(triangle vertexOutput IN[3], inout TriangleStream<geometryOutput> triStream)
	{
		
		float3 pos = IN[0].vertex;
		float3 vNormal = IN[0].normal;
		float4 vTangent = IN[0].tangent;
		float3 vBinormal = cross(vNormal, vTangent) * vTangent.w;

		float2 uv0 = pos.xz * _GrassLoadMap_ST.xy + _GrassLoadMap_ST.zw;
		float grassVisibility = tex2Dlod(_GrassLoadMap, float4(uv0, 0, 0)).r;

		if (grassVisibility >= _GrassThreshold) {
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
			//uv for the wind
			float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
			float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
			float3 wind = normalize(float3(windSample.x, windSample.y, 0));
			float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);
			//With direction and bend
			//With wind
			float3x3 transformationMatrix = mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix), bendRotationMatrix);


			

			//Width and Height of a blade
			float height = (rand(pos.zyx) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
			float width = (rand(pos.xzy) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
			float forward = rand(pos.yyz) * _BladeForward;
			

			//Base of the blade needs to stay attached to its surface during wind
			float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);


			//Get real point of intersection, based on global coordinates
			float3 realPointOfIntersection = _Collision.xyz - mul(unity_ObjectToWorld, float4(0.0, 0.0, 0.0, 1.0));

			//Blade segments
			for (int i = 0; i < BLADE_SEGMENTS; i++)
			{
				float t = i / (float)BLADE_SEGMENTS;
				float segmentHeight = height * t;
				float segmentWidth = width * (1 - t);
				float segmentForward = pow(t, _BladeCurve) * forward;


				float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;

				if (i != 0) {
					//collision detection with the ball, as long as the vertex is not at the base
					float3 collision = GetCollisionVector(pos, realPointOfIntersection);
					pos += collision * _CollisionStrength;
				}
				
				triStream.Append(GenerateGrassVertex(pos, segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
				triStream.Append(GenerateGrassVertex(pos, -segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
			}

			//collision detection with the ball
			float3 collision = GetCollisionVector(pos, realPointOfIntersection);
			pos += collision * _CollisionStrength;
			triStream.Append(GenerateGrassVertex(pos, 0, height, forward, float2(0.5, 1), transformationMatrix));

			
		}
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
			#pragma geometry geo // SubShader uses the geometry shader
			#pragma target 4.6
			#pragma hull hull
			#pragma domain domain
			#pragma multi_compile_fwdbase
            
			#include "Lighting.cginc"

			float4 _TopColor;
			float4 _BottomColor;
			float4 _DryTopColor;
			float4 _DryBottomColor;
			float _TranslucentGain;
			sampler2D _GrassTexture;
			float _DryGrassEnabled;
			


	
			float4 frag(geometryOutput i, fixed facing : VFACE) : SV_Target // Added UV
            {	
				
				//return SHADOW_ATTENUATION(i); //for the shadow
				float3 normal = facing > 0 ? i.normal : -i.normal;
				float shadow = SHADOW_ATTENUATION(i);
				float NdotL = saturate(saturate(dot(normal, _WorldSpaceLightPos0)) + _TranslucentGain) * shadow;
				float4 colorTexture = tex2D(_GrassTexture, i.uv);
				float randoms = rand(facing);

				float3 ambient = ShadeSH9(float4(normal, 1));
				float4 lightIntensity = NdotL * _LightColor0 + float4(ambient, 1);
				float4 color;
				if (_DryGrassEnabled == 1) {
					if (randoms <= 0.75)
						color = colorTexture * lerp(_BottomColor, _TopColor * lightIntensity, i.uv.y);
					else
						color = colorTexture * lerp(_DryBottomColor, _DryTopColor * lightIntensity, i.uv.y);
				}
				else color = colorTexture * lerp(_BottomColor, _TopColor * lightIntensity, i.uv.y);
				
				return color;
            }
            ENDCG
        }

		Pass
		{
			Tags
			{
				"LightMode" = "ShadowCaster" //second pass for the shadows
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