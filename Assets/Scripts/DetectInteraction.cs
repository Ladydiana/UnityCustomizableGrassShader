using System.Collections;
using System.Collections.Generic;
using UnityEngine;

// passes parameters from ball to shader
// adapted from here: https://gamedev.center/tutorial-how-to-make-an-interactive-grass-shader-in-unity
[ExecuteInEditMode]
public class DetectInteraction : MonoBehaviour
{
    [SerializeField] private Material material;
    [SerializeField] [Range(0, 10)] private float radius;
    [SerializeField] [Range(-1, 5)] private float heightOffset;
    private Transform cachedTransform;
    private readonly int grassCollisionProperty = Shader.PropertyToID("_Collision");

    private void Awake()
    {
        cachedTransform = transform;
    }

    private void Update()
    {
        if (material == null)
        {
            return;
        }

        var position = cachedTransform.position;
        material.SetVector(grassCollisionProperty, new Vector4(position.x, position.y + heightOffset, position.z, radius));
    }
}

