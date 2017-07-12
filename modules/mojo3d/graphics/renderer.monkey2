
Namespace mojo3d.graphics

#rem

Renderpasses:

0 : render background.

1 : render deferred MRT.

2 : render shadow map.

3 : render deferred light quad.

#end

#rem monkeydoc @hidden
#end
Class RenderOp
	Field material:Material
	Field vbuffer:VertexBuffer
	Field ibuffer:IndexBuffer
	Field instance:Entity
	Field bones:Mat4f[]
	Field order:Int
	Field count:Int
	Field first:Int
End

#rem monkeydoc @hidden
#end
Class RenderQueue
	
	Property OpaqueOps:Stack<RenderOp>()
		Return _opaqueOps
	End
	
	Property TransparentOps:Stack<RenderOp>()
		Return _transparentOps
	End
	
	Method Clear()
		_opaqueOps.Clear()
		_transparentOps.Clear()
	End
	
	Method AddRenderOp( material:Material,vbuffer:VertexBuffer,ibuffer:IndexBuffer,order:Int,count:Int,first:Int )
		Local op:=New RenderOp
		op.material=material
		op.vbuffer=vbuffer
		op.ibuffer=ibuffer
		op.order=order
		op.count=count
		op.first=first
		_opaqueOps.Push( op )
	End
	
	Method AddRenderOp( material:Material,vbuffer:VertexBuffer,ibuffer:IndexBuffer,instance:Entity,order:Int,count:Int,first:Int )
		Local op:=New RenderOp
		op.material=material
		op.vbuffer=vbuffer
		op.ibuffer=ibuffer
		op.instance=instance
		op.order=order
		op.count=count
		op.first=first
		_opaqueOps.Push( op )
	End
	
	Method AddRenderOp( material:Material,vbuffer:VertexBuffer,ibuffer:IndexBuffer,instance:Entity,bones:Mat4f[],order:Int,count:Int,first:Int )
		Local op:=New RenderOp
		op.material=material
		op.vbuffer=vbuffer
		op.ibuffer=ibuffer
		op.instance=instance
		op.bones=bones
		op.order=order
		op.count=count
		op.first=first
		_opaqueOps.Push( op )
	End
	
	Private
	
	Field _opaqueOps:=New Stack<RenderOp>
	Field _transparentOps:=New Stack<RenderOp>
	
End

#rem monkeydoc The Renderer class.
#end
Class Renderer

	#rem monkeydoc @hidden
	#end
	Method New()
	
		_device=New GraphicsDevice( 0,0 )
		
		_uniforms=New UniformBlock( 1 )
		
		_device.BindUniformBlock( _uniforms )

		_csmSplits=New Float[]( 1,20,60,180,1000 )

		_quadVertices=New VertexBuffer( New Vertex3f[](
			New Vertex3f( 0,1,0 ),
			New Vertex3f( 1,1,0 ),
			New Vertex3f( 1,0,0 ),
			New Vertex3f( 0,0,0 ) ) )
			
		_defaultEnv=Texture.Load( "asset::textures/env_default.jpg",TextureFlags.FilterMipmap|TextureFlags.Cubemap )
		
		_skyboxShader=Shader.Open( "skybox" )
		
		For Local i:=0 Until _nullBones.Length
			_nullBones[i]=New Mat4f
		Next
	End
	
	#rem monkeydoc Size of the cascading shadow map texture.
	
	Must be a power of 2 size.
	
	Defaults to 4096.
		
	#end
	Property CSMTextureSize:Float()
		
		Return _csmSize
		
	Setter( size:Float )
		Assert( Log2( size )=Floor( Log2( size ) ),"CSMTextureSize must be a power of 2" )
		
		_csmSize=size
	End
	
	#rem monkeydoc Array containing the Z depths of the cascading shadow map frustum splits.
	
	Defaults to Float[]( 1,20,60,180,1000 ).
		
	#end
	Property CSMSplitDepths:Float[]()
		
		Return _csmSplits
	
	Setter( splits:Float[] )
		Assert( splits.Length=5,"CSMSplitDepths array must have 5 elements" )
		
		_csmSplits=splits
	End
	
	#rem monkeydoc Gets the current renderer.
	#end
	Function GetCurrent:Renderer()
		
		Global _current:=New DeferredRenderer
		
		Return _current
	End
	
	#rem monkeydoc @hidden
	#end
	Method Render( scene:Scene,camera:Camera,device:GraphicsDevice )
		
		Validate()
	
		_renderTarget=device.RenderTarget
		_renderTargetSize=device.RenderTargetSize
		_renderViewport=device.Viewport
		
		SetScene( scene )
		
		SetCamera( camera )
		
		OnRender()
	End
	
	'***** INTERNAL *****
	
	Protected

	Field _csmSize:=4096
	Field _csmSplits:=New Float[]( 1,20,60,180,1000 )
	
	Field _uniforms:UniformBlock
	Field _device:GraphicsDevice
	
	Field _csmTexture:Texture
	Field _csmTarget:RenderTarget
	Field _quadVertices:VertexBuffer
	Field _skyboxShader:Shader
	Field _defaultEnv:Texture
	
	Field _renderQueue:=New RenderQueue
	Field _spriteQueue:=New RenderQueue
	Field _spriteBuffer:=New SpriteBuffer
	
	Field _nullBones:=New Mat4f[64]
	
	'Per render...
	'
	Field _renderTarget:RenderTarget
	Field _renderTargetSize:Vec2i
	Field _renderViewport:Recti
	
	Field _scene:Scene
	Field _camera:Camera
	
'	Field _projectionMatrix:Mat4f
'	Field _viewMatrix:AffineMat4f
'	Field _viewProjectionMatrix:Mat4f
	
	Method OnRender() Virtual
	End

	Method SetScene( scene:Scene )
	
		_scene=scene
		
		_uniforms.SetFloat( "Time",Now() )
		_uniforms.SetTexture( "SkyTexture",_scene.SkyTexture )
		
		_uniforms.SetVec4f( "ClearColor",_scene.ClearColor )
		_uniforms.SetVec4f( "AmbientDiffuse",_scene.AmbientLight )
	
		_uniforms.SetTexture( "ShadowTexture",_csmTexture )
		_uniforms.SetVec4f( "ShadowSplits",New Vec4f( _csmSplits[1],_csmSplits[2],_csmSplits[3],_csmSplits[4] ) )
		
		Local env:Texture
		
		If _scene.SkyTexture
			env=_scene.SkyTexture
		Else If _scene.EnvTexture
			env=_scene.EnvTexture
		Else
			env=_defaultEnv
		Endif
		
		_uniforms.SetTexture( "EnvTexture",env )
		
		_renderQueue.Clear()
		
		For Local model:=Eachin _scene.Models
			
			model.OnRender( _renderQueue )
		Next
		
		For Local terrain:=Eachin _scene.Terrains
			
			terrain.OnRender( _renderQueue )
		Next
	End

	Method SetCamera( camera:Camera )
	
		_camera=camera
		
		Local envMat:=_camera.WorldMatrix.m
		Local viewMat:=_camera.InverseWorldMatrix
		Local projMat:=_camera.ProjectionMatrix
		Local invProjMat:=-projMat
			
		_uniforms.SetMat3f( "EnvMatrix",envMat )
		_uniforms.SetMat4f( "ProjectionMatrix",projMat )
		_uniforms.SetMat4f( "InverseProjectionMatrix",invProjMat )
		_uniforms.SetFloat( "DepthNear",_camera.Near )
		_uniforms.SetFloat( "DepthFar",_camera.Far )
		
		_spriteQueue.Clear()
		
		_spriteBuffer.AddSprites( _spriteQueue,_scene.Sprites,_camera )
	End
	
	'MX2_RENDERPASS 0
	'
	Method RenderBackground() Virtual
	
		If _scene.SkyTexture
		
			_device.ColorMask=ColorMask.None
			_device.DepthMask=True
			
			_device.Clear( Null,1.0 )
			
			_device.ColorMask=ColorMask.All
			_device.DepthMask=False
			_device.DepthFunc=DepthFunc.Always
			_device.BlendMode=BlendMode.Opaque
			_device.CullMode=CullMode.None
			_device.RenderPass=0
			
			_device.VertexBuffer=_quadVertices
			_device.Shader=_skyboxShader
			_device.Render( 4,1 )
			
		Else
			_device.ColorMask=ColorMask.All
			_device.DepthMask=True
		
			_device.Clear( _scene.ClearColor,1.0 )

		Endif
		
	End
	
	'MX2_RNDERPASS 1
	'
	Method RenderAmbient() Virtual
		
		_device.ColorMask=ColorMask.All
		_device.DepthMask=True
		_device.DepthFunc=DepthFunc.LessEqual
		_device.RenderPass=1
		
		RenderRenderOps( _renderQueue.OpaqueOps,_camera.InverseWorldMatrix,_camera.ProjectionMatrix )
	End
	
	'MX2_RENDERPASS 0
	'
	Method RenderSprites()
	
		_device.ColorMask=ColorMask.All
		_device.DepthMask=False
		_device.DepthFunc=DepthFunc.Always
		_device.RenderPass=0

		RenderRenderOps( _spriteQueue.OpaqueOps,_camera.InverseWorldMatrix,_camera.ProjectionMatrix )
	End
	
	'MX2_RENDERPASS 2
	'
	Method RenderCSMShadows( light:Light )
	
		'Perhaps use a different device for CSM...?
		'
		Local t_rtarget:=_device.RenderTarget
		Local t_viewport:=_device.Viewport
		Local t_scissor:=_device.Scissor

		_device.RenderTarget=_csmTarget
		_device.Viewport=New Recti( 0,0,_csmTarget.Size )
		_device.Scissor=_device.Viewport
		_device.ColorMask=ColorMask.None
		_device.DepthMask=True
		_device.Clear( Null,1.0 )
		
		If light.ShadowsEnabled
		
			_device.DepthFunc=DepthFunc.LessEqual
			_device.BlendMode=BlendMode.Opaque
			_device.CullMode=CullMode.Back
			_device.RenderPass=2
	
			Local invLightMatrix:=light.InverseWorldMatrix
			Local viewLight:=invLightMatrix * _camera.WorldMatrix
			
			For Local i:=0 Until _csmSplits.Length-1
				
				Local znear:=_csmSplits[i]
				Local zfar:=_csmSplits[i+1]
				
				Local splitProj:=Mat4f.Perspective( _camera.Fov,_camera.Aspect,znear,zfar )
							
				Local invSplitProj:=-splitProj
				
				Local bounds:=Boxf.EmptyBounds
				
				For Local z:=-1 To 1 Step 2
					For Local y:=-1 To 1 Step 2
						For Local x:=-1 To 1 Step 2
							Local c:=New Vec3f( x,y,z )				'clip coords
							Local v:=invSplitProj * c				'clip->view
							Local l:=viewLight * v					'view->light
							bounds|=l
						Next
					Next
				Next
				
				bounds.min.z-=100
				
				Local lightProj:=Mat4f.Ortho( bounds.min.x,bounds.max.x,bounds.min.y,bounds.max.y,bounds.min.z,bounds.max.z )
				
				'set matrices for next pass...
				_uniforms.SetMat4f( "ShadowMatrix"+i,lightProj * viewLight )
				
				Local size:=_csmTexture.Size,hsize:=size/2
				
				Select i
				Case 0 _device.Viewport=New Recti( 0,0,hsize.x,hsize.y )
				Case 1 _device.Viewport=New Recti( hsize.x,0,size.x,hsize.y )
				Case 2 _device.Viewport=New Recti( 0,hsize.y,hsize.x,size.y )
				Case 3 _device.Viewport=New Recti( hsize.x,hsize.y,size.x,size.y )
				End
				
				_device.Scissor=_device.Viewport
					
				RenderRenderOps( _renderQueue.OpaqueOps,invLightMatrix,lightProj )
			Next
			
		Endif
		
		_device.RenderTarget=t_rtarget
		_device.Viewport=t_viewport
		_device.Scissor=t_scissor
	End

	Method Validate()
		
		If Not _csmTexture Or _csmSize<>_csmTexture.Size.x
			
			If _csmTexture _csmTexture.Discard()
			If _csmTarget _csmTarget.Discard()
			
			_csmTexture=New Texture( _csmSize,_csmSize,PixelFormat.Depth32F,TextureFlags.Dynamic )
			_csmTarget=New RenderTarget( Null,_csmTexture )
			
		Endif
	End
	
	Method RenderRenderOps( ops:Stack<RenderOp>,viewMatrix:AffineMat4f,projMatrix:Mat4f )
		
		_uniforms.SetMat4f( "ViewMatrix",viewMatrix )
		_uniforms.SetMat4f( "ProjectionMatrix",projMatrix )
		_uniforms.SetMat4f( "InverseProjectionMatrix",-projMatrix )
		
		For Local op:=Eachin ops
			
			Local model:=op.instance
			
			Local modelMat:= model ? model.WorldMatrix Else New AffineMat4f
			Local modelViewMat:=viewMatrix * modelMat
			Local modelViewProjMat:=projMatrix * modelViewMat
			Local modelViewNormMat:=~-modelViewMat.m
				
			_uniforms.SetMat4f( "ModelMatrix",modelMat )
			_uniforms.SetMat4f( "ModelViewMatrix",modelViewMat )
			_uniforms.SetMat4f( "ModelViewProjectionMatrix",modelViewProjMat )
			_uniforms.SetMat3f( "ModelViewNormalMatrix",modelViewNormMat )
			
			If op.bones
				_uniforms.SetMat4fArray( "BoneMatrices",op.bones )
			Else
				_uniforms.SetMat4fArray( "BoneMatrices",_nullBones )
			End
			
			Local material:=op.material
			
			_device.Shader=material.Shader
			_device.BindUniformBlock( material.Uniforms )
			_device.BlendMode=material.BlendMode
			_device.CullMode=material.CullMode
			_device.VertexBuffer=op.vbuffer
			_device.IndexBuffer=op.ibuffer
			_device.RenderIndexed( op.order,op.count,op.first )
			
		Next
	End

End